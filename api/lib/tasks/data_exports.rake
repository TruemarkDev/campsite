# frozen_string_literal: true

namespace :data_exports do
  desc "Create the private data-export bucket and apply its expiry policy"
  task prepare_storage: :environment do
    configured_bucket = ENV["DATA_EXPORT_S3_BUCKET"]
    abort "DATA_EXPORT_S3_BUCKET must be set explicitly" if configured_bucket.blank?

    bucket = DATA_EXPORT_BUCKET
    abort "DATA_EXPORT_BUCKET does not match DATA_EXPORT_S3_BUCKET" unless bucket.name == configured_bucket

    client = bucket.client

    begin
      client.head_bucket(bucket: bucket.name)
    rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchBucket
      client.create_bucket(bucket: bucket.name)
    end

    client.put_bucket_lifecycle_configuration(
      bucket: bucket.name,
      lifecycle_configuration: {
        rules: [
          {
            id: "expire-campsite-data-exports",
            status: "Enabled",
            filter: { prefix: "exports/" },
            expiration: { days: 3 },
            abort_incomplete_multipart_upload: { days_after_initiation: 1 },
          },
        ],
      },
    )

    puts "Prepared private data-export storage bucket #{bucket.name.inspect}"
  end
end
