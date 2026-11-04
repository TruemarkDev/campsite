# frozen_string_literal: true

class PostIndexHealthJob < BaseJob
  sidekiq_options queue: "background"

  def perform
    db_count = Post.all.count
    indexed_count = SearchDocument.where(resource_type: "Post").count

    if (db_count - indexed_count).abs > 15
      Sentry.capture_message("Post index health check failed", extra: { db_count: db_count, indexed_count: indexed_count })
    end
  end
end
