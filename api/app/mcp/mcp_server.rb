# frozen_string_literal: true

# Builds a per-request MCP::Server wired with the Campsite tool catalog and the
# authenticated request context. A fresh server is built per request so the
# server_context (and therefore the acting user) is never shared across requests.
class McpServer
  NAME = "campsite"
  TITLE = "Campsite"
  VERSION = "1.0.0"

  INSTRUCTIONS = <<~TEXT.strip
    Campsite MCP server. Tools act as the connected Campsite user across every
    organization they belong to. Most tools require an `org_slug` argument — call
    `list_organizations` first to discover the organizations and slugs available.
    Reads are paginated; writes (create_post, add_comment, add_reaction) are
    additive only and require the matching write OAuth scope.
  TEXT

  def self.build(context:)
    resource = McpResource.new(context: context)

    server = CampsiteMcpServer.new(
      resources_provider: -> { resource.list },
      name: NAME,
      title: TITLE,
      version: VERSION,
      instructions: INSTRUCTIONS,
      tools: McpToolRegistry.tools,
      prompts: McpPromptRegistry.prompts,
      resource_templates: McpResource.templates,
      # Resource subscriptions (resources.subscribe) are intentionally NOT advertised
      # here — they require a server→client stream the remote transport hasn't been
      # shown to hold (see add-mcp-tier-3 tasks 4.x, the subscription spike).
      capabilities: { tools: {}, prompts: { listChanged: true }, resources: { listChanged: true } },
      server_context: context,
    )

    # Resolve any campsite:// URI under the authenticated context, mapping our
    # resource errors onto JSON-RPC errors.
    server.resources_read_handler do |params|
      resource.read(params[:uri])
    rescue McpResource::ResourceError => e
      raise MCP::Server::RequestHandlerError.new(e.message, params, error_type: :invalid_params)
    rescue ActiveRecord::RecordNotFound
      raise MCP::Server::ResourceNotFoundError.new(params[:uri], params)
    rescue Pundit::NotAuthorizedError
      raise MCP::Server::RequestHandlerError.new("You are not authorized to read this resource.", params, error_type: :invalid_params)
    end

    server
  end
end
