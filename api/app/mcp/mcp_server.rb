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
    MCP::Server.new(
      name: NAME,
      title: TITLE,
      version: VERSION,
      instructions: INSTRUCTIONS,
      tools: McpToolRegistry.tools,
      server_context: context,
    )
  end
end
