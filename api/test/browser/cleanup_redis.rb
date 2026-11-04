# frozen_string_literal: true

require "redis"

run_id = ENV.fetch("BROWSER_TEST_RUN_ID")
prefix = ENV.fetch("SYNC_REDIS_PREFIX")
raise "Unsafe browser Redis prefix" unless run_id.match?(/\A[a-f0-9]{16}\z/) && prefix == "campsite-browser-#{run_id}"

redis = Redis.new(url: ENV.fetch("SYNC_REDIS_URL"))
redis.scan_each(match: "#{prefix}*").each { |key| redis.unlink(key) }
redis.close
