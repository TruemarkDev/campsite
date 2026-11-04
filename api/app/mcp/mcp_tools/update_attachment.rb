# frozen_string_literal: true

module McpTools
  class UpdateAttachment < McpTool
    include ResolvesAttachmentSubject

    tool_name "update_attachment"
    description "Update preview path or dimensions for a post/note attachment. Requires the subject's write scope."
    input_schema(org_scoped_schema(
      properties: ResolvesAttachmentSubject::SUBJECT_PROPERTIES.merge(
        attachment_id: { type: "string" },
        preview_file_path: { type: "string" },
        width: { type: "integer", minimum: 0 },
        height: { type: "integer", minimum: 0 },
      ),
      required: ["subject_type", "subject_id", "attachment_id"],
    ))

    private

    def execute
      actor, organization, member = organization_context!
      subject = resolve_attachment_subject!(actor, organization)
      attachment = subject.attachments.find_by!(public_id: input[:attachment_id])
      attrs = input.slice(:preview_file_path, :width, :height)
      raise ToolError, "Provide preview_file_path, width, or height." if attrs.empty?

      attachment.update!(attrs)
      data_response(serialize(AttachmentSerializer, attachment, organization: organization, member: member))
    end
  end
end
