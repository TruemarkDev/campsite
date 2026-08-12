# frozen_string_literal: true

require "base64"

# Remote MCP server mounted in the Rails API, served over Streamable HTTP at `/mcp`.
#
# Each request is authenticated with a Doorkeeper bearer token that carries the
# `mcp` scope; the token's resource owner (a User) becomes the acting identity for
# every tool. The JSON-RPC framing (initialize / tools/list / tools/call) is
# handled by the `mcp` gem; we own auth, the Current context, and dispatch.
class McpController < ActionController::API
  include McpDiscoverable

  MODERN_PROTOCOL_VERSION = "2026-07-28"
  NAMED_METHOD_PARAMS = {
    "tools/call" => :name,
    "prompts/get" => :name,
    "resources/read" => :uri,
  }.freeze

  before_action :require_mcp_enabled!
  before_action :authenticate_mcp!
  before_action :require_mcp_scope!

  def handle
    # No server-initiated streaming for this tools-only server: clients use POST
    # for JSON-RPC. GET (SSE stream) is unsupported; DELETE (end session) is a no-op.
    return head(:method_not_allowed) if request.get?
    return head(:no_content) if request.delete?

    context = McpRequestContext.new(token: doorkeeper_token)
    server = McpServer.build(context: context)

    request_body = JSON.parse(request.raw_post, symbolize_names: true)
    return render_header_mismatch(request_body) unless valid_modern_headers?(request_body)

    response_json = server.handle(request_body)

    if response_json.nil?
      # The request was a notification (e.g. notifications/initialized); no response body.
      head(:accepted)
    else
      render(json: response_json)
    end
  rescue JSON::ParserError
    render(json: server.handle_json(request.raw_post))
  end

  private

  def authenticate_mcp!
    return if doorkeeper_token&.accessible?

    # RFC 9728: point unauthenticated clients at the protected-resource metadata so
    # they can discover how to authorize.
    response.set_header("WWW-Authenticate", %(Bearer resource_metadata="#{protected_resource_metadata_url}"))
    render(
      json: { error: "invalid_token", error_description: "A valid bearer access token is required." },
      status: :unauthorized,
    )
  end

  def require_mcp_scope!
    return if doorkeeper_token.scopes.exists?("mcp")

    render(
      json: { error: "insufficient_scope", error_description: "The 'mcp' scope is required to use the MCP server." },
      status: :forbidden,
    )
  end

  # Optional Flipper kill-switch for gradual rollout. The endpoint is enabled by
  # default; it is only blocked when an operator has registered the `mcp_server`
  # feature and turned it off (globally or for this user).
  def require_mcp_enabled!
    return if mcp_feature_enabled?

    head(:not_found)
  end

  def mcp_feature_enabled?
    feature = Flipper.feature(:mcp_server)
    return true unless feature.exist?

    Flipper.enabled?(:mcp_server, current_mcp_user)
  end

  def current_mcp_user
    return unless doorkeeper_token

    if defined?(@current_mcp_user)
      @current_mcp_user
    else
      @current_mcp_user = User.find_by(id: doorkeeper_token.resource_owner_id)
    end
  end

  def valid_modern_headers?(body)
    return true unless modern_protocol_request?(body)

    return false unless request.headers["Mcp-Method"] == body[:method]

    body_protocol_version = body.dig(:params, :_meta, CampsiteMcpServer::PROTOCOL_VERSION_META_KEY.to_sym)
    if body_protocol_version && request.headers["MCP-Protocol-Version"] != body_protocol_version
      return false
    end

    name_param = NAMED_METHOD_PARAMS[body[:method]]
    return true unless name_param

    decoded_header_value(request.headers["Mcp-Name"]) == body.dig(:params, name_param)
  end

  def modern_protocol_request?(body)
    return true if body[:method] == MCP::Methods::SERVER_DISCOVER

    protocol_version = if body[:method] == MCP::Methods::INITIALIZE
      body.dig(:params, :protocolVersion)
    else
      body.dig(:params, :_meta, CampsiteMcpServer::PROTOCOL_VERSION_META_KEY.to_sym)
    end

    protocol_version == MODERN_PROTOCOL_VERSION
  end

  def render_header_mismatch(body)
    render(
      json: {
        jsonrpc: "2.0",
        id: body[:id],
        error: {
          code: MCP::ErrorCodes::HEADER_MISMATCH,
          message: "Header mismatch: Mcp-Method and Mcp-Name must match the JSON-RPC body",
        },
      },
      status: :bad_request,
    )
  end

  def decoded_header_value(value)
    return value unless value&.start_with?("=?base64?") && value.end_with?("?=")

    Base64.strict_decode64(value.delete_prefix("=?base64?").delete_suffix("?="))
  rescue ArgumentError
    nil
  end
end
