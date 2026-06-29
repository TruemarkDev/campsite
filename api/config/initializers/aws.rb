# frozen_string_literal: true

Aws.config.update(
  region: Rails.application.credentials.dig(:aws, :region),
  credentials: Aws::Credentials.new(
    Rails.application.credentials.dig(:aws, :access_key_id),
    Rails.application.credentials.dig(:aws, :secret_access_key),
  ),
  endpoint: Rails.application.credentials.dig(:aws, :endpoint),
  force_path_style: Rails.application.credentials.dig(:aws, :force_path_style) || false,
)

S3_BUCKET = Aws::S3::Resource.new.bucket(Rails.application.credentials&.dig(:aws, :s3_bucket) || "")
