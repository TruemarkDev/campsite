# frozen_string_literal: true

module McpTools
  # Create an attachment from a file already uploaded to S3 (via `create_upload`) and
  # link it to a post or note. Mirrors Posts::AttachmentsController#create /
  # Notes::AttachmentsController#create: `subject.attachments.create!` authorizing the
  # subject's `:update?`. Requires the write scope matching the subject
  # (`write_post` / `write_note`).
  class AttachFile < McpTool
    include ResolvesAttachmentSubject

    # The safe subset of Attachment create params an agent supplies; the rest
    # (figma/remote-node, video specifics) are out of scope for MCP uploads.
    ATTACHMENT_PROPERTIES = {
      file_path: { type: "string", description: "S3 object key returned by create_upload." },
      file_type: { type: "string", description: "MIME type of the uploaded file, e.g. \"image/png\"." },
      name: { type: "string", description: "Optional display name for the file." },
      width: { type: "integer", description: "Optional pixel width (for images/video)." },
      height: { type: "integer", description: "Optional pixel height (for images/video)." },
      preview_file_path: { type: "string", description: "Optional S3 key of a preview image." },
    }.freeze

    PERMITTED_KEYS = [:file_path, :file_type, :name, :width, :height, :preview_file_path].freeze

    tool_name "attach_file"
    description "Attach a file (already uploaded via create_upload) to a post or note."
    input_schema(org_scoped_schema(
      properties: SUBJECT_PROPERTIES.merge(ATTACHMENT_PROPERTIES),
      required: ["subject_type", "subject_id", "file_path", "file_type"],
    ))

    private

    def execute
      actor, organization, member = organization_context!
      subject = resolve_attachment_subject!(actor, organization)

      attachment = subject.attachments.create!(attachment_params)
      data = serialize(AttachmentSerializer, attachment, organization: organization, member: member)
      data_response(data)
    end

    def attachment_params
      PERMITTED_KEYS.each_with_object({}) do |key, params|
        params[key] = input[key] if input.key?(key)
      end
    end
  end
end
