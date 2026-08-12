# frozen_string_literal: true

# A thin MCP::Server subclass that computes the resources catalog lazily.
#
# The gem takes `resources:` as a static array and iterates it at construction, so a
# dynamic, per-user resources list would otherwise run its DB queries on *every* MCP
# request (including every tools/call). Overriding `list_resources` defers that work
# to an actual `resources/list` call. The handler the server binds at construction
# (`method(:list_resources)`) resolves to this override.
class CampsiteMcpServer < MCP::Server
  STATIC_CATALOG_TTL_MS = 1.hour.in_milliseconds
  USER_RESOURCE_TTL_MS = 1.minute.in_milliseconds
  PRIVATE_CACHE_SCOPE = "private"

  MODERN_PROTOCOL_VERSION = "2026-07-28"
  PROTOCOL_VERSION_META_KEY = "io.modelcontextprotocol/protocolVersion"
  CLIENT_INFO_META_KEY = "io.modelcontextprotocol/clientInfo"
  CLIENT_CAPABILITIES_META_KEY = "io.modelcontextprotocol/clientCapabilities"

  def initialize(resources_provider:, **kwargs)
    @resources_provider = resources_provider
    super(**kwargs)
  end

  private

  # mcp 1.1 advertises and negotiates 2026-07-28, but its modern transport path
  # is not complete yet. Keep the SDK's legacy initialize flow intact while
  # adding the request-scoped envelope and result fields required by the modern
  # lifecycle for Campsite's already-stateless, per-request server instances.
  def handle_request(request, method, **kwargs)
    handler = super
    return handler unless handler

    lambda do |params|
      modern = modern_request?(params)
      validate_modern_request!(params, request) if modern

      result = handler.call(params)
      modern || method == MCP::Methods::SERVER_DISCOVER ? modern_result(result) : result
    end
  end

  def list_resources(request)
    self.resources = @resources_provider.call
    super.merge(ttlMs: USER_RESOURCE_TTL_MS, cacheScope: PRIVATE_CACHE_SCOPE)
  end

  def list_tools(request)
    super.merge(ttlMs: STATIC_CATALOG_TTL_MS, cacheScope: PRIVATE_CACHE_SCOPE)
  end

  def list_prompts(request)
    super.merge(ttlMs: STATIC_CATALOG_TTL_MS, cacheScope: PRIVATE_CACHE_SCOPE)
  end

  def list_resource_templates(request)
    super.merge(ttlMs: STATIC_CATALOG_TTL_MS, cacheScope: PRIVATE_CACHE_SCOPE)
  end

  def modern_request?(params)
    meta = params.is_a?(Hash) ? params[:_meta] || params["_meta"] : nil
    protocol_version = read_meta(meta, PROTOCOL_VERSION_META_KEY)
    !protocol_version.nil?
  end

  def validate_modern_request!(params, request)
    meta = params[:_meta] || params["_meta"]
    protocol_version = read_meta(meta, PROTOCOL_VERSION_META_KEY)
    client_capabilities = read_meta(meta, CLIENT_CAPABILITIES_META_KEY)
    client_info = read_meta(meta, CLIENT_INFO_META_KEY)

    unless client_capabilities.is_a?(Hash)
      raise MCP::Server::RequestHandlerError.new(
        "Invalid Request: modern requests require `#{CLIENT_CAPABILITIES_META_KEY}` in `_meta`",
        request,
        error_type: :invalid_request,
      )
    end

    if client_info && (!client_info.is_a?(Hash) || read_meta(client_info, "name").nil? || read_meta(client_info, "version").nil?)
      raise MCP::Server::RequestHandlerError.new(
        "Invalid Request: `#{CLIENT_INFO_META_KEY}` must contain name and version",
        request,
        error_type: :invalid_request,
      )
    end

    return if protocol_version == MODERN_PROTOCOL_VERSION

    raise MCP::Server::UnsupportedProtocolVersionError.new(protocol_version, request)
  end

  def modern_result(result)
    return result unless result.is_a?(Hash)

    metadata = result[:_meta] || result["_meta"] || {}
    result.merge(
      resultType: MCP::ResultType::COMPLETE,
      _meta: metadata.merge("io.modelcontextprotocol/serverInfo" => server_info),
    )
  end

  def read_meta(meta, key)
    return unless meta.is_a?(Hash)

    meta[key] || meta[key.to_sym]
  end
end
