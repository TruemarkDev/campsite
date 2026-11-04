# frozen_string_literal: true

require "benchmark"
require "json"
require "webmock"
require "factory_bot_rails"

connection = ApplicationRecord.connection
abort "Disposable local test database required" unless Rails.env.test? && connection.pool.db_config.database == "campsite_api_perf_review" && %w[127.0.0.1 localhost].include?(connection.pool.db_config.configuration_hash[:host])
connection.execute("SET statement_timeout = '15s'")
WebMock.disable_net_connect!
Sidekiq.testing!(:fake)
FactoryBot.find_definitions unless FactoryBot.factories.registered?(:post)

def measure_write
  counts = []
  times = Array.new(5) do |i|
    count = 0
    listener = ->(_name, _start, _finish, _id, payload) { count += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] }
    elapsed = Benchmark.realtime do
      ActiveSupport::Notifications.subscribed(listener, "sql.active_record") { yield i }
    end
    counts << count
    elapsed * 1000
  end
  { median_ms: times.sort[2].round(3), queries: counts }
end

results = {}
ApplicationRecord.transaction do
  member = FactoryBot.create(:organization_membership)
  project = FactoryBot.create(:project, organization: member.organization)
  posts = Array.new(30) { |i| FactoryBot.create(:post, member: member, organization: member.organization, project: project, title: "Synthetic post #{i}") }
  post = posts.first
  before = SearchDocument.where(resource_type: 'Post', resource_id: post.id).pick(Arel.sql('ctid::text'))
  results[:unchanged_refresh] = measure_write { post.refresh_search_document }
  after = SearchDocument.where(resource_type: 'Post', resource_id: post.id).pick(Arel.sql('ctid::text'))
  results[:unchanged_row_rewritten] = before != after
  results[:title_update] = measure_write { |i| post.update!(title: "Synthetic title #{i}") }
  results[:author_rename_30_posts] = measure_write { |i| member.user.update!(name: "Synthetic author #{i}") }
  results[:project_rename_30_posts] = measure_write { |i| project.update!(name: "Synthetic project #{i}") }
  raise ActiveRecord::Rollback
end
puts "WRITE_JSON=#{JSON.generate(results)}"
