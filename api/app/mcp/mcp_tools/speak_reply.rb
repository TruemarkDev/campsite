# frozen_string_literal: true

module McpTools
  class SpeakReply < McpTool
    include ResolvesAttachmentSubject

    tool_name "speak_reply"
    description "Synthesize speech and attach the resulting MP3 to a post or note."
    input_schema(org_scoped_schema(
      properties: ResolvesAttachmentSubject::SUBJECT_PROPERTIES.merge(
        text: { type: "string", description: "Text to synthesize as speech." },
        voice_id: { type: "string", description: "Optional provider-specific voice id." },
      ),
      required: ["subject_type", "subject_id", "text"],
    ))

    private

    def execute
      actor, organization, member = organization_context!
      subject = resolve_attachment_subject!(actor, organization)
      raise ToolError, "A text argument is required." if input[:text].blank?

      audio = Tts::Service.call(text: input[:text], voice_id: input[:voice_id].presence || Current.user.voice_id)
      attachment = AttachmentUploader.put_and_attach!(
        subject: subject,
        bytes: audio.fetch(:bytes),
        file_type: audio.fetch(:content_type),
        name: "spoken-reply.mp3",
      )
      data_response(serialize(AttachmentSerializer, attachment, organization: organization, member: member))
    rescue Tts::Error => e
      raise ToolError, e.message
    end
  end
end
