# frozen_string_literal: true

require "benchmark"
require "json"

connection = SearchDocument.connection
abort "Disposable local test database required" unless Rails.env.test? && connection.pool.db_config.database == "campsite_api_perf_review" && %w[127.0.0.1 localhost].include?(connection.pool.db_config.configuration_hash[:host])
connection.execute("SET statement_timeout = '15s'")
columns = %w[resource_type resource_id organization_id fields title content resource_created_at]
updates = SearchDocument::UPDATE_COLUMNS.map { |column| "#{column} = EXCLUDED.#{column}" }.join(", ")
base_sql = "INSERT INTO search_documents (#{columns.join(', ')}) SELECT #{columns.join(', ')} FROM search_documents ORDER BY id LIMIT 100 ON CONFLICT (resource_type, resource_id) DO UPDATE SET #{updates}"
filtered_sql = base_sql + " WHERE (#{SearchDocument::UPDATE_COLUMNS.map { |c| "search_documents.#{c}" }.join(', ')}) IS DISTINCT FROM (#{SearchDocument::UPDATE_COLUMNS.map { |c| "EXCLUDED.#{c}" }.join(', ')})"

def snapshot(connection)
  connection.execute("SELECT pg_stat_force_next_flush()")
  connection.execute("SELECT pg_stat_clear_snapshot()")
  {
    total_bytes: connection.select_value("SELECT pg_total_relation_size('search_documents')"),
    health: connection.select_one("SELECT n_live_tup, n_dead_tup, n_tup_upd, n_tup_hot_upd, last_vacuum, last_autovacuum, last_analyze, last_autoanalyze FROM pg_stat_user_tables WHERE relname = 'search_documents'")
  }
end

results = { before: snapshot(connection) }
{ unconditional: base_sql, unchanged_guard: filtered_sql }.each do |name, sql|
  affected = 0
  elapsed = Benchmark.realtime do
    10.times do
      SearchDocument.transaction do
        affected += connection.execute(sql).cmd_tuples
        raise ActiveRecord::Rollback
      end
    end
  end
  results[name] = { affected_rows: affected, elapsed_ms: (elapsed * 1000).round(3), snapshot: snapshot(connection) }
end
results[:vacuum_ms] = (Benchmark.realtime { connection.execute("VACUUM (ANALYZE) search_documents") } * 1000).round(3)
results[:after_vacuum] = snapshot(connection)
puts "MAINTENANCE_JSON=#{JSON.generate(results)}"
