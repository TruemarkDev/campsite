# frozen_string_literal: true

# Run via script/test-postgresql runner script/benchmark_postgresql_search.rb.
# PG_TEST_DATABASE must name the disposable database below. Never reads user data.
require "benchmark"
require "json"

connection = SearchDocument.connection
connection.execute("SET statement_timeout = '15s'")
abort "Disposable local test database required" unless Rails.env.test? && connection.pool.db_config.database == "campsite_api_perf_review" && %w[127.0.0.1 localhost].include?(connection.pool.db_config.configuration_hash[:host])

if ARGV.delete("--seed")
  connection.execute("TRUNCATE search_documents")
  connection.execute(<<~SQL.squish)
    INSERT INTO search_documents (resource_type, resource_id, organization_id, fields, title, content, resource_created_at)
    SELECT 'Post', i, org,
      jsonb_build_object('id', i, 'public_id', 'synthetic-' || i, 'organization_id', org,
        'user_id', i % 200, 'project_id', i % 50, 'discarded_at', NULL,
        'title', title, 'description', body, 'tag_ids', jsonb_build_array(i % 12)),
      title, body, timestamp '2026-01-01' + i * interval '1 minute'
    FROM (
      SELECT i, CASE WHEN i % 2 = 0 THEN 1 ELSE 2 + i % 11 END AS org,
        CASE WHEN i % 997 = 0 THEN 'quasarlaunch ' ELSE '' END ||
        CASE WHEN i % 5 = 0 THEN 'Planning engineering release ' ELSE 'Design feedback discussion ' END || i AS title,
        repeat('engineering architecture release feedback documentation collaboration ', 12) ||
        md5(i::text) || ' ' || md5((i * 31)::text) AS body
      FROM generate_series(1, 40000) i
    ) dataset
  SQL
end

# Standardize maintenance state; timings below are warm-cache synthetic results.
connection.execute("VACUUM (ANALYZE) search_documents")

organization = Struct.new(:id).new(1)
cases = {
  blank: { query: "", sort_by_date: true },
  common: { query: "plan" },
  rare: { query: "quasarlaunch" },
  typo: { query: "enginering" },
  absent: { query: "xylophonenomatch" },
  author: { query: "plan", user_id: 10 },
}
results = cases.transform_values do |options|
  Post.scoped_search(organization: organization, limit: 10, **options) # warm schema/type caches
  sql = []
  listener = ->(_name, _start, _finish, _id, payload) { sql << payload[:sql] if payload[:sql].match?(/\A(?:SELECT|WITH)/) && payload[:name] != "SCHEMA" && !payload[:cached] }
  result = nil
  ActiveSupport::Notifications.subscribed(listener, "sql.active_record") do
    SearchDocument.uncached { result = Post.scoped_search(organization: organization, limit: 10, **options) }
  end
  plans = sql.map { |query| JSON.parse(connection.select_value("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) #{query}"))[0] }
  timings = Array.new(7) do
    Benchmark.realtime { SearchDocument.uncached { Post.scoped_search(organization: organization, limit: 10, **options) } } * 1000
  end.sort
  timings_with_count = Array.new(7) do
    Benchmark.realtime { SearchDocument.uncached { Post.scoped_search(organization: organization, limit: 10, **options).total_count } } * 1000
  end.sort
  { median_with_count_ms: timings_with_count[3].round(3), queries: sql.length, returned: result.length, total_count: result.total_count, median_ms: timings[3].round(3), max_ms: timings.last.round(3), sql: sql, plans: plans }
end

sizes = connection.select_all(<<~SQL.squish).to_a
  SELECT indexrelname, pg_relation_size(indexrelid) AS bytes
  FROM pg_stat_user_indexes WHERE relname = 'search_documents' ORDER BY indexrelname
SQL
health = connection.select_all(<<~SQL.squish).to_a
  SELECT n_live_tup, n_dead_tup, n_tup_upd, n_tup_hot_upd, last_vacuum, last_autovacuum, last_analyze, last_autoanalyze
  FROM pg_stat_user_tables WHERE relname = 'search_documents'
SQL
output = { rows: SearchDocument.count, postgres: connection.select_value("SELECT version()"), cases: results, indexes: sizes, table_bytes: connection.select_value("SELECT pg_table_size('search_documents')"), health: health }
puts "PERF_JSON=#{JSON.generate(output)}"
