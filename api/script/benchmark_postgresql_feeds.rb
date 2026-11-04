# frozen_string_literal: true

require "json"
require "webmock"
require "factory_bot_rails"

connection = ApplicationRecord.connection
abort "Disposable local test database required" unless Rails.env.test? && connection.pool.db_config.database == "campsite_api_perf_review" && %w[127.0.0.1 localhost].include?(connection.pool.db_config.configuration_hash[:host])
connection.execute("SET statement_timeout = '15s'")
WebMock.disable_net_connect!
Sidekiq.testing!(:fake)
FactoryBot.find_definitions unless FactoryBot.factories.registered?(:project)
connection.execute("VACUUM (ANALYZE) posts, projects, organization_memberships, project_memberships")
results = {}
ApplicationRecord.transaction do
  projects = Array.new(12) do
    member = FactoryBot.create(:organization_membership)
    FactoryBot.create(:project, organization: member.organization, creator: member).tap do |project|
      FactoryBot.create(:project_membership, project: project, organization_membership: member)
    end
  end
  tenants = projects.each_with_index.map { |p, i| "(#{i}, #{p.id}, #{p.organization_id}, #{p.creator_id})" }.join(', ')
  connection.execute(<<~SQL.squish)
    INSERT INTO posts (id, project_id, organization_id, organization_membership_id, public_id, title, last_activity_at, published_at, created_at, updated_at)
    SELECT 1000000+i, project_id, organization_id, member_id, 'p' || lpad(i::text,11,'0'),
      'Synthetic feed item', timestamp '2026-01-01' + i * interval '1 minute',
      timestamp '2026-01-01', timestamp '2026-01-01', timestamp '2026-01-01'
    FROM generate_series(1,40000) i
    JOIN (VALUES #{tenants}) AS tenant(n,project_id,organization_id,member_id)
      ON n = CASE WHEN i % 2 = 0 THEN 0 ELSE 1 + i % 11 END
  SQL
  connection.execute("ANALYZE posts, projects, organization_memberships, project_memberships, user_subscriptions")
  [projects.first, projects.last].each_with_index do |project, index|
    user = project.creator.user
    base = Post.kept.with_published_state.with_active_project.leaves.where(organization_id: project.organization_id)
    scopes = {
      feed: base.viewable_by(user).reorder(last_activity_at: :desc, id: :desc).limit(51),
      project_feed: project.kept_published_posts.leaves.viewable_by(user).reorder(published_at: :desc, id: :desc).limit(51),
      subscribed_feed: base.with_project_membership_for(user).or(base.with_subscription_for(user)).viewable_by(user).reorder(last_activity_at: :desc, id: :desc).limit(51),
    }
    scopes.each do |name, scope|
      sql = scope.to_sql
      plans = Array.new(3) { JSON.parse(connection.select_value("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) #{sql}"))[0] }
      results["#{index.zero? ? 'large' : 'small'}_#{name}"] = { sql: sql, median_execution_ms: plans.map { |p| p['Execution Time'] }.sort[1], plan: plans[1] }
    end
  end
  raise ActiveRecord::Rollback
end
puts "FEED_JSON=#{JSON.generate(results)}"
