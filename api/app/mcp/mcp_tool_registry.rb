# frozen_string_literal: true

# The catalog of tools advertised over MCP. Reads, bounded writes, self-state, and
# explicit lifecycle operations are registered; no bulk or primary-content
# hard-delete tool exists. Every entry receives a machine-readable contract below.
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
    # CreateFollowUp writes a `follow_up` row but is a deliberate, self-only,
    # `mcp`-scope-only exemption grouped with reads — see the class comment.
    McpTools::CreateFollowUp,
    # CreateUpload only mints short-lived S3 credentials and writes nothing in
    # Campsite, so it gates on `mcp` alone — grouped with reads. The matching write
    # scope is enforced later by attach_file when the attachment is actually created.
    McpTools::CreateUpload,
    McpTools::GetAttachmentTranscript,
  ].freeze

  WRITE_TOOLS = [
    McpTools::CreatePost,
    McpTools::AddComment,
    McpTools::AddReaction,
    McpTools::SendMessage,
    McpTools::CreateMessageThread,
    McpTools::CreateNote,
    McpTools::UpdateNote,
    McpTools::ResolvePost,
    McpTools::UpdatePost,
    McpTools::ReplyToComment,
    McpTools::CreateProject,
    McpTools::AttachFile,
    McpTools::UploadAttachment,
    McpTools::SpeakReply,
    McpTools::UpdateComment,
    McpTools::RemoveComment,
    McpTools::UpdateMessage,
    McpTools::RemoveMessage,
    McpTools::UpdateProject,
    McpTools::ArchiveProject,
    McpTools::UnarchiveProject,
    McpTools::RemovePost,
    McpTools::RemoveNote,
    McpTools::UpdateAttachment,
    McpTools::RemoveAttachment,
    McpTools::EditNote,
    McpTools::PinToProject,
    McpTools::RemoveProjectPin,
  ].freeze

  SELF_TOOLS = [
    McpTools::MarkNotificationRead,
    McpTools::CreateFollowUp,
    McpTools::UpdateFollowUp,
    McpTools::CancelFollowUp,
    McpTools::RemoveReaction,
    McpTools::SetFavorite,
    McpTools::SetReadState,
  ].freeze

  ADDITIONAL_READ_TOOLS = [
    McpTools::ReadComment,
    McpTools::ReadProject,
    McpTools::ListFollowUps,
  ].freeze

  DESTRUCTIVE_TOOLS = [
    McpTools::CancelFollowUp,
    McpTools::RemoveReaction,
    McpTools::RemoveComment,
    McpTools::RemoveMessage,
    McpTools::ArchiveProject,
    McpTools::RemovePost,
    McpTools::RemoveNote,
    McpTools::RemoveAttachment,
    McpTools::RemoveProjectPin,
    McpTools::SetFavorite,
  ].freeze

  IDEMPOTENT_TOOLS = [
    McpTools::MarkNotificationRead,
    McpTools::UpdateFollowUp,
    McpTools::UpdateComment,
    McpTools::UpdateMessage,
    McpTools::UpdateProject,
    McpTools::ArchiveProject,
    McpTools::UnarchiveProject,
    McpTools::UpdateAttachment,
    McpTools::SetFavorite,
    McpTools::SetReadState,
  ].freeze

  REQUIRED_SCOPES = {
    "create_post" => ["mcp", "write_post"],
    "add_comment" => ["mcp", "write_post"],
    "add_reaction" => ["mcp", "write_post"],
    "resolve_post" => ["mcp", "write_post"],
    "update_post" => ["mcp", "write_post"],
    "reply_to_comment" => ["mcp", "write_post"],
    "update_comment" => ["mcp", "write_post"],
    "remove_comment" => ["mcp", "write_post"],
    "remove_post" => ["mcp", "write_post"],
    "send_message" => ["mcp", "write_message"],
    "create_message_thread" => ["mcp", "write_message"],
    "update_message" => ["mcp", "write_message"],
    "remove_message" => ["mcp", "write_message"],
    "create_note" => ["mcp", "write_note"],
    "update_note" => ["mcp", "write_note"],
    "edit_note" => ["mcp", "write_note"],
    "remove_note" => ["mcp", "write_note"],
    "create_project" => ["mcp", "write_project"],
    "update_project" => ["mcp", "write_project"],
    "archive_project" => ["mcp", "write_project"],
    "unarchive_project" => ["mcp", "write_project"],
    "attach_file" => ["mcp", "write_post|write_note"],
    "upload_attachment" => ["mcp", "write_post|write_note"],
    "speak_reply" => ["mcp", "write_post|write_note"],
    "update_attachment" => ["mcp", "write_post|write_note"],
    "remove_attachment" => ["mcp", "write_post|write_note"],
    "pin_to_project" => ["mcp", "write_project"],
    "remove_project_pin" => ["mcp", "write_project"],
  }.freeze

  def tools
    catalog = (READ_TOOLS + ADDITIONAL_READ_TOOLS + SELF_TOOLS + WRITE_TOOLS).uniq
    catalog.each { |tool| apply_contract!(tool) }
    catalog.sort_by(&:name_value)
  end

  def contract_for(tool)
    name = tool.name_value
    pure_read = (READ_TOOLS + ADDITIONAL_READ_TOOLS).include?(tool) && SELF_TOOLS.exclude?(tool)
    {
      read_only: pure_read,
      destructive: DESTRUCTIVE_TOOLS.include?(tool),
      idempotent: pure_read || IDEMPOTENT_TOOLS.include?(tool),
      open_world: [McpTools::CreateUpload, McpTools::UploadAttachment, McpTools::SpeakReply, McpTools::EditNote].include?(tool),
      scopes: REQUIRED_SCOPES.fetch(name, ["mcp"]),
      category: pure_read ? "read" : (SELF_TOOLS.include?(tool) ? "self" : "write"),
    }
  end

  private

  def apply_contract!(tool)
    contract = contract_for(tool)
    tool.output_schema(type: "object", additionalProperties: true) unless tool.output_schema_value
    tool.annotations(
      title: tool.name_value.tr("_", " ").titleize,
      read_only_hint: contract[:read_only],
      destructive_hint: contract[:destructive],
      idempotent_hint: contract[:idempotent],
      open_world_hint: contract[:open_world],
    )
    tool.meta(
      "campsite/requiredScopes" => contract[:scopes],
      "campsite/category" => contract[:category],
      "campsite/contractVersion" => 1,
    )
  end
end
