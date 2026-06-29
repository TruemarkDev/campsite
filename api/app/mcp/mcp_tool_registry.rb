# frozen_string_literal: true

# The catalog of tools advertised over MCP. Reads and additive writes only — no
# hard-delete or bulk-destructive tools are registered (see the change spec), so
# the connector is safe by default.
module McpToolRegistry
  extend self

  READ_TOOLS = [
    McpTools::ListOrganizations,
    McpTools::ListMembers,
    McpTools::ListProjects,
    McpTools::ListPosts,
    McpTools::SearchPosts,
    McpTools::ReadPost,
    McpTools::ListMessageThreads,
    McpTools::ReadMessages,
    McpTools::ListNotes,
    McpTools::ReadNote,
    McpTools::Whoami,
    McpTools::ListNotifications,
    # MarkNotificationRead writes `read_at` but is a deliberate, self-only,
    # `mcp`-scope-only exemption grouped with reads — see the class comment.
    McpTools::MarkNotificationRead,
  ].freeze

  WRITE_TOOLS = [
    McpTools::CreatePost,
    McpTools::AddComment,
    McpTools::AddReaction,
    McpTools::SendMessage,
    McpTools::CreateMessageThread,
    McpTools::CreateNote,
    McpTools::UpdateNote,
  ].freeze

  def tools
    READ_TOOLS + WRITE_TOOLS
  end
end
