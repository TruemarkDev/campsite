BEGIN READ ONLY;
SET LOCAL statement_timeout = '10s';
SET LOCAL lock_timeout = '1s';
SELECT jsonb_build_object(
  'format_version', 1,
  'captured_at', clock_timestamp(),
  'database', current_database(),
  'application_role_oid', (SELECT oid::text FROM pg_roles WHERE rolname = 'campsite_app'),
  'server_start', pg_postmaster_start_time(),
  'in_recovery', pg_is_in_recovery(),
  'postgresql_version', current_setting('server_version'),
  'statement_stats', (SELECT to_jsonb(i) FROM pg_stat_statements_info i),
  'database_stats', (
    SELECT to_jsonb(d) - 'datid' FROM pg_stat_database d WHERE datname = current_database()
  ),
  'statements', (
    SELECT coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb) FROM (
      SELECT queryid::text, userid::text AS role_oid, toplevel, calls, rows,
        total_exec_time, min_exec_time, max_exec_time, mean_exec_time,
        shared_blks_hit, shared_blks_read, temp_blks_written, wal_bytes,
        ARRAY(SELECT relation FROM unnest(ARRAY[
          'posts', 'notes', 'comments', 'search_documents', 'organization_memberships',
          'project_memberships', 'message_threads', 'messages', 'permissions', 'users'
        ]) relation WHERE query ~ ('(^|[^a-zA-Z0-9_])' || relation || '([^a-zA-Z0-9_]|$)')) AS relation_tags,
        CASE WHEN ltrim(query) ~* '^(SELECT|INSERT|UPDATE|DELETE|WITH)\M'
          THEN upper(substring(ltrim(query) FROM '^([A-Za-z]+)'))
          ELSE 'OTHER' END AS operation
      FROM pg_stat_statements
      WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
        AND userid = (SELECT oid FROM pg_roles WHERE rolname = 'campsite_app')
      ORDER BY total_exec_time DESC, queryid, toplevel, userid
    ) s
  ),
  'tables', (
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) FROM (
      SELECT schemaname, relname, n_live_tup, n_dead_tup,
        n_tup_ins, n_tup_upd, n_tup_del, n_tup_hot_upd,
        last_vacuum, last_autovacuum, last_analyze, last_autoanalyze,
        vacuum_count, autovacuum_count, analyze_count, autoanalyze_count,
        pg_total_relation_size(relid) AS total_bytes
      FROM pg_stat_user_tables ORDER BY schemaname, relname
    ) t
  ),
  'indexes', (
    SELECT coalesce(jsonb_agg(to_jsonb(i)), '[]'::jsonb) FROM (
      SELECT schemaname, relname, indexrelname, idx_scan, idx_tup_read, idx_tup_fetch,
        pg_relation_size(indexrelid) AS index_bytes
      FROM pg_stat_user_indexes ORDER BY schemaname, relname, indexrelname
    ) i
  )
);
COMMIT;
