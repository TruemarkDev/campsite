# frozen_string_literal: true

if Rails.env.production?
  Rack::MiniProfiler.config.storage_options = {
    url: ENV["REDIS_URL"] || Rails.application.credentials&.redis&.url,
    expires_in: 60 * 60,
  }
  Rack::MiniProfiler.config.storage = Rack::MiniProfiler::RedisStore
end
