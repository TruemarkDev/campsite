# frozen_string_literal: true

module McpTools
  class GetAttachmentTranscript < McpTool
    tool_name "get_attachment_transcript"
    description "Get the transcription status and plain-text transcript for an attachment."
    input_schema(org_scoped_schema(
      properties: {
        attachment_id: { type: "string", description: "Public id of the attachment." },
      },
      required: ["attachment_id"],
    ))

    private

    def execute
      actor, organization, = organization_context!
      attachment = Attachment.includes(:subject).find_by!(public_id: input[:attachment_id])
      subject = attachment.subject
      raise ActiveRecord::RecordNotFound unless subject&.organization == organization

      authorization_subject = subject.is_a?(Message) ? subject.message_thread : subject.try(:subject) || subject
      authorize!(actor, authorization_subject, :show?)

      data_response({
        attachment_id: attachment.public_id,
        transcript: attachment.transcript,
        transcription_job_status: attachment.transcription_job_status,
        subject_type: subject.class.name,
        subject_id: subject.public_id,
      })
    end
  end
end
