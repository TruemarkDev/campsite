# frozen_string_literal: true

module McpTools
  # Mint presigned S3 POST fields the client uses to upload a file's bytes directly to
  # S3 — the same two-step flow the web app uses (GET presigned-fields → upload →
  # create the attachment). Mirrors `PostsController#presigned_fields`.
  #
  # This writes nothing in Campsite (it only issues short-lived S3 credentials), so it
  # gates on the `mcp` scope alone. After uploading, call `attach_file` with the
  # returned `key` as `file_path` to create the attachment. For small files, prefer
  # `upload_attachment`, which does both server-side in one call.
  class CreateUpload < McpTool
    tool_name "create_upload"
    description "Get presigned S3 upload fields for a file. Upload the bytes to the returned `url` " \
      "(multipart POST with the returned fields), then call attach_file with the returned `key` as file_path. " \
      "For small files, upload_attachment is simpler. Writes nothing on its own."
    input_schema(org_scoped_schema(
      properties: {
        mime_type: { type: "string", description: "MIME type of the file you will upload, e.g. \"image/png\"." },
      },
      required: ["mime_type"],
    ))

    private

    def execute
      _actor, organization, member = organization_context!

      mime_type = input[:mime_type]
      raise ToolError, "A mime_type argument is required." if mime_type.blank?

      fields = organization.generate_post_presigned_post_fields(mime_type)
      data = serialize(PresignedPostFieldsSerializer, fields, organization: organization, member: member)
      data_response(data)
    end
  end
end
