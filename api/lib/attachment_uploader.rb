# frozen_string_literal: true

class AttachmentUploader
  def self.put_and_attach!(subject:, bytes:, file_type:, name: nil)
    organization = subject.organization
    key = organization.generate_post_s3_key(file_type)
    S3_BUCKET.object(key).put(body: bytes, content_type: file_type)
    subject.attachments.create!(file_path: key, file_type: file_type, name: name)
  end
end
