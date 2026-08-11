# frozen_string_literal: true

Aws.config.update(
  region: ENV["S3_REGION"] || Rails.application.credentials.dig(:aws, :region),
  credentials: Aws::Credentials.new(
    ENV["S3_ACCESS_KEY_ID"] || Rails.application.credentials.dig(:aws, :access_key_id),
    ENV["S3_SECRET_ACCESS_KEY"] || Rails.application.credentials.dig(:aws, :secret_access_key),
  ),
  endpoint: ENV["S3_ENDPOINT"] || Rails.application.credentials.dig(:aws, :endpoint),
  force_path_style: ActiveModel::Type::Boolean.new.cast(
    ENV.fetch("S3_FORCE_PATH_STYLE", Rails.application.credentials.dig(:aws, :force_path_style) || false),
  ),
)

S3_BUCKET = Aws::S3::Resource.new.bucket(
  ENV["S3_BUCKET"] || Rails.application.credentials&.dig(:aws, :s3_bucket) || "",
)
