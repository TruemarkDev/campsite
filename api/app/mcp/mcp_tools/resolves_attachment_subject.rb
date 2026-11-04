# frozen_string_literal: true

module McpTools
  # Shared by `attach_file` and `upload_attachment`: resolve the polymorphic subject
  # an attachment is being linked to, require the write scope that matches the
  # subject, and authorize the subject's `:update?` policy — exactly as the REST
  # attachment controllers do (Posts::AttachmentsController / Notes::AttachmentsController).
  #
  # Scoped to posts and notes: those are the subjects with a standalone REST
  # attachment-create endpoint. Comment and message attachments are set at creation
  # time in the REST API (no post-hoc create), so they are out of scope here.
  module ResolvesAttachmentSubject
    SUBJECT_SCOPES = { "post" => :write_post, "note" => :write_note }.freeze

    SUBJECT_PROPERTIES = {
      subject_type: {
        type: "string",
        enum: SUBJECT_SCOPES.keys,
        description: "What to attach the file to: \"post\" or \"note\".",
      },
      subject_id: { type: "string", description: "Public id of the post or note to attach to." },
    }.freeze

    # Returns the resolved subject (a Post or Note) after requiring the matching
    # write scope and authorizing `:update?`.
    def resolve_attachment_subject!(actor, organization)
      type = input[:subject_type]
      scope = SUBJECT_SCOPES[type]
      raise ToolError, "subject_type must be one of: #{SUBJECT_SCOPES.keys.join(", ")}." unless scope

      require_scope!(scope)

      subject =
        case type
        when "post" then organization.kept_posts.find_by!(public_id: input[:subject_id])
        when "note" then organization.notes.kept.find_by!(public_id: input[:subject_id])
        end

      authorize!(actor, subject, :update?)
      subject
    end
  end
end
