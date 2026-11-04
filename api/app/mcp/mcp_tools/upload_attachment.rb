# frozen_string_literal: true

module McpTools
  # Convenience for agent-produced artifacts: accept the file's bytes inline (base64),
  # upload them to S3 server-side, and create+link the attachment in one call — so the
  # client doesn't have to perform the multipart S3 POST itself.
  #
  # Because the bytes travel through the JSON-RPC transport, this is bounded by a hard
  # size cap; larger files MUST use `create_upload` + `attach_file`. Same write scope
  # and `:update?` authorization as `attach_file`.
  class UploadAttachment < McpTool
    include ResolvesAttachmentSubject

    # Decoded-size ceiling for inline uploads. Kept well below typical org file limits
    # so a large artifact is routed to the presigned path rather than the transport.
    MAX_INLINE_UPLOAD_BYTES = 5.megabytes

    tool_name "upload_attachment"
    description "Upload a small file inline (base64) and attach it to a post or note in one call. " \
      "For files larger than 5 MB, use create_upload + attach_file instead."
    input_schema(org_scoped_schema(
      properties: ResolvesAttachmentSubject::SUBJECT_PROPERTIES.merge(
        content: { type: "string", description: "The file's bytes, base64-encoded. Max 5 MB decoded." },
        file_type: { type: "string", description: "MIME type of the file, e.g. \"image/png\"." },
        name: { type: "string", description: "Optional display name for the file." },
      ),
      required: ["subject_type", "subject_id", "content", "file_type"],
    ))

    private

    def execute
      actor, organization, member = organization_context!
      subject = resolve_attachment_subject!(actor, organization)

      file_type = input[:file_type]
      raise ToolError, "A file_type argument is required." if file_type.blank?

      bytes = decode_content!

      attachment = AttachmentUploader.put_and_attach!(
        subject: subject,
        bytes: bytes,
        file_type: file_type,
        name: input[:name],
      )
      data = serialize(AttachmentSerializer, attachment, organization: organization, member: member)
      data_response(data)
    end

    def decode_content!
      raw = input[:content]
      raise ToolError, "A content argument (base64) is required." if raw.blank?

      bytes =
        begin
          Base64.strict_decode64(raw)
        rescue ArgumentError
          raise ToolError, "content must be valid base64."
        end

      if bytes.bytesize > MAX_INLINE_UPLOAD_BYTES
        raise ToolError,
          "File is larger than the #{MAX_INLINE_UPLOAD_BYTES / 1.megabyte} MB inline limit. " \
            "Use create_upload + attach_file for larger files."
      end

      bytes
    end
  end
end
