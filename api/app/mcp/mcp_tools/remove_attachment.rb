# frozen_string_literal: true

module McpTools
  class RemoveAttachment < McpTool
    include ResolvesAttachmentSubject

    tool_name "remove_attachment"
    description "Permanently remove an attachment record from a post or note. Requires the subject's write scope."
    input_schema(org_scoped_schema(
      properties: ResolvesAttachmentSubject::SUBJECT_PROPERTIES.merge(attachment_id: { type: "string" }),
      required: ["subject_type", "subject_id", "attachment_id"],
    ))

    private

    def execute
      actor, organization, _member = organization_context!
      subject = resolve_attachment_subject!(actor, organization)
      attachment = subject.attachments.find_by!(public_id: input[:attachment_id])
      id = attachment.public_id
      attachment.destroy!
      data_response({ removed: true, attachment_id: id, subject_id: subject.public_id })
    end
  end
end
