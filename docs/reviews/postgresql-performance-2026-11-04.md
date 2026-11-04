# PostgreSQL performance review and improvements

Implementation follow-up: [PostgreSQL history, API generation and failure coverage](reliability-follow-up-2026-11-04.md) records the subsequent changes, passing checks and live acceptance limits. This report remains the dated assessment.

Date: 2026-11-04. Project: Campsite only. Tracking: `campsite-991`.
Baseline checkout: `main` at `2f0416b`, with the uncommitted PostgreSQL search migration and earlier modernization work present. This report compares the native search implementation before and after this optimization pass, not Elasticsearch against PostgreSQL.

## Outcome

Implemented measured improvements for search reads, unchanged refreshes, connection budgeting, and project-feed pagination. Production inspection was read-only; server settings and live data were not changed. Deployment remains pending.

Raw application query plans, SQL, timings, index sizes and redacted live observations are in [the JSON evidence](postgresql-performance-2026-11-04.json). Reproduction scripts are guarded to require the dedicated local test database `campsite_api_perf_review`.

## 1. Search plans and latency

Method: PostgreSQL 18.6 on this Mac; 40,000 synthetic documents across 12 tenants, with 20,000 in the largest tenant. Bodies contain repeated engineering/topic text plus unique tokens. Each timing is a seven-run warm-cache median measured through the Rails search helper, with query caching disabled. EXPLAIN uses `ANALYZE, BUFFERS, FORMAT JSON`. This fixture stresses repeated transcript-like text; it is not a copy of production and these are not user-facing latency guarantees.

Times below are milliseconds. Before always computed a total count; after computes it only when requested. Compare the first and last numeric columns for the same count behavior. The middle column shows ordinary callers that only consume items.

| Query | Before, including count | After, items only | After, including count |
|---|---:|---:|---:|
| blank | 76.99 | 0.60 | 2.76 |
| common | 27.61 | 20.88 | 29.10 |
| rare | 4.19 | 3.50 | 4.62 |
| typo | 5197.53 | 529.09 | 822.54 |
| absent | 22.92 | 3.67 | 6.46 |
| author | 24.73 | 6.93 | 8.35 |

Changes in `SearchDocument` and migration `20261104010000`:

- Added an ordered partial index for tenant/resource browsing, so blank queries can fetch a page without scanning and sorting the tenant's documents.
- Added an expression index for author-filtered tenant queries, including the discarded-state expression. This also gives ANALYZE useful expression statistics.
- Replaced the full-body trigram index with a trigram index over `strip(content_vector)::text`. This native PostgreSQL expression removes repeated positions and compares deduplicated lexemes, reducing work for repetitive text. Existing full-text vectors remain unchanged.
- Made total counting lazy and memoized. Groups still receive an accurate total; mixed search, mentions and ordinary list callers avoid an unused count query.
- Materialized the indexed candidate plan for the two-hit typo-fallback probe. EXPLAIN exposed a LIMIT row-goal choosing a sequential scan for absent prefixes; the CTE prevents that particular probe regression without changing global planner settings.

Index bytes on the synthetic search table changed from **43.83 MiB to 45.36 MiB**, including the new B-tree indexes. This is observed storage, not a percentage-bloat estimate.

Rare/common cases do not all improve in these small samples; the clearest wins are blank browsing, absent queries, author filtering and repetitive-text typo matching. Broad fuzzy matches remain the expensive path. Comparing normalized lexemes also changes approximate multi-word fuzzy matching/ranking from comparisons against original sentence text; exact prefix matching and title-phrase preference remain in place. Representative query-quality acceptance is still required before live rollout.

## 2. Write and rename costs

A separate factory-created fixture measures actual model callbacks in a transaction, with 30 posts for one author/project. Jobs are faked and external network access is blocked. Each number is a five-run median; the fixture is rolled back afterward.

| Operation | Before ms | After ms | SQL statements |
|---|---:|---:|---:|
| unchanged_refresh | 5.53 | 6.00 | 8 → 7 |
| title_update | 6.46 | 7.92 | 9 → 8 |
| author_rename_30_posts | 182.86 | 170.70 | 245 → 215 |
| project_rename_30_posts | 198.16 | 148.67 | 242 → 212 |

The refresh now obtains its locked source row in one query instead of fetching and reloading it. The upsert uses `IS DISTINCT FROM` to skip identical snapshots. A test checks the physical tuple location: unchanged refreshes retain it, changed content replaces it, and existing rollback/deletion tests still pass.

Single-write wall-clock medians are noisy and not uniformly faster; the deterministic improvements are one fewer query per refresh and zero heap/index rewrites for unchanged snapshots. Author/project renames still refresh affected posts synchronously and therefore scale with fan-out. Their measured cost is recorded rather than described as eliminated.

## 3. API feed and membership query review

The feed fixture uses 40,000 posts with real factory-created tenant, project and membership records. Plans use the application's `viewable_by`, project-membership/subscription scopes and normal ordering. These measure the base SQL query, not controller hydration, network, or rendering. Each number is the median of three EXPLAIN executions in milliseconds.

| Scope | Before | After |
|---|---:|---:|
| large_feed | 0.144 | 0.129 |
| large_project_feed | 10.095 | 0.056 |
| large_subscribed_feed | 0.131 | 0.132 |
| small_feed | 0.261 | 0.264 |
| small_project_feed | 5.736 | 0.057 |
| small_subscribed_feed | 0.272 | 0.258 |

General and subscribed feeds already used efficient paths after representative ANALYZE statistics were present. No extra organization-feed or membership indexes were added. The measured project-feed bottleneck sorted a large set sharing the publication date. Migration `20261104020000` adds the partial `(project_id, published_at DESC, id DESC)` index for kept, published, non-stale posts. It matches `Projects::PostsController`'s default pagination and was tested by migrating down and back up on the disposable database.

Existing membership indexes include the user lookup, organization/user membership lookup and project-membership existence paths. This review found no measured reason to add more of them. Broader live query-frequency prioritization remains limited by the absence of statement-level history.

## 4. Connection budget

Before: database pool = `RAILS_MAX_THREADS * RAILS_MAX_ASYNC_QUERIES`, defaulting to 25. Rails' actual global async executor default was four threads; the old pool variable did not configure that executor.

After: default pool = `max(web threads, Sidekiq concurrency) + async concurrency + 1`, giving **10**. `RAILS_MAX_ASYNC_QUERIES` now configures the real global executor in development and production. `SIDEKIQ_CONCURRENCY` configures Sidekiq's normal worker concurrency, and `DB_POOL` remains an explicit pool override. The export worker keeps its separate concurrency of one and conservatively inherits the same default pool cap.

| Declared process role | Processes | Before pool capacity | After pool capacity |
|---|---:|---:|---:|
| Puma | 2 | 50 | 20 |
| Sidekiq normal worker | 1 | 25 | 10 |
| Sidekiq export worker | 1 | 25 | 10 |
| Total | 4 | **100** | **40** |

These are configured upper bounds, not reserved connections or observed usage. Additional replicas, console sessions and release overlap must be included separately; a full overlap of those four roles would permit 80 connections with the new defaults.

Read-only verification against the declared leader `campsite-pg-a` on Groot confirmed **200 max connections**, `pg_is_in_recovery = false`, and autovacuum enabled. The probe saw one Campsite connection (itself); this is an idle snapshot, not peak-demand evidence. Other databases were not inspected. No claim about cluster-wide spare capacity is made from that one observation.

Pool tests cover defaults, worker/async overrides, explicit pool overrides and invalid thread input. Guidance: [Rails async executor and pool sizing](https://guides.rubyonrails.org/v8.0.2/configuring.html#config-active-record-global-executor-concurrency).

## 5. Vacuum and index growth

On the synthetic fixture, ten batches of 100 unchanged snapshots produced:

| Upsert behavior | Rows rewritten | Elapsed ms |
|---|---:|---:|
| Unconditional update | 1000 | 207.12 |
| New unchanged guard | 0 | 58.18 |

Unconditional updates grew total relation storage from 120.80 to 125.39 MiB and increased estimated dead tuples. The guarded pass caused no additional row rewrites. Standard VACUUM/ANALYZE then reported zero dead tuples and took 818.04 ms. Some physical space remained allocated for reuse, which is expected; VACUUM FULL was not used.

Live, read-only observations: 777 posts, 69 notes and 1,849 comments. Persisted planner row estimates matched these actual counts. Runtime tuple counters were zero and maintenance timestamps absent; they do not establish either bloat-free health or maintenance freshness. `track_counts` and autovacuum are on, with default scale factors 0.2 for vacuum and 0.1 for analyze, and a one-minute naptime. No evidence justified changing global autovacuum thresholds or memory settings.

`pg_stat_statements` is not installed in the Campsite database. Capturing real query frequency/latency and observing maintenance over normal traffic are the next operational measurements. Enabling preload-dependent instrumentation requires its own controlled rollout; no PostgreSQL restart was performed here. PostgreSQL's [vacuum guidance](https://www.postgresql.org/docs/current/routine-vacuuming.html) and [GIN vacuum behavior](https://www.postgresql.org/docs/current/sql-vacuum.html) inform these recommendations.

## Validation and rollout

- Full local Rails suite: **4,287 tests, 14,041 assertions, zero failures/errors/skips**, using two processes with the local native-pg GSS workaround.
- Focused search/write/controller/config suite: 178 tests, 770 assertions, all passed.
- Fresh-schema search/pool suite: 14 tests, 56 assertions, all passed. Final schema reload also recreated all four new optimization indexes successfully.
- Project pagination index rollback/reapply succeeded on the disposable database.
- All 51 changed Ruby files pass RuboCop; final whitespace checks pass. Brakeman reports the same four warnings in unchanged files, with no warning in the search implementation. After the full suite, a constant-only SQL builder was made an equivalent static literal for scanner clarity; the 14-test search/pool suite passed again. Benchmark scripts also received formatting-only corrections.

The migrations create/drop indexes concurrently. The two four-key search indexes carry narrow Strong Migrations advisory exceptions: their measured queries constrain both tenant/resource keys and require both ordering keys, or constrain all four filter keys. There is no blanket safety override. If a concurrent build is interrupted, inspect `pg_index.indisvalid` and remove an invalid artifact concurrently before retrying.

Apply these changes with the pending [PostgreSQL search rollout](../deployment/postgresql-search.md), then run ANALYZE after the backfill and compare real traffic. No production migration, maintenance write, deployment, commit or push was performed in this pass. Pending operational measurements do not invalidate the local results, but the local results do not establish live performance acceptance.

## Reproduce locally

```bash
PG_TEST_DATABASE=campsite_api_perf_review script/test-postgresql db:create db:schema:load
PG_TEST_DATABASE=campsite_api_perf_review script/test-postgresql runner script/benchmark_postgresql_search.rb --seed
PG_TEST_DATABASE=campsite_api_perf_review script/test-postgresql runner script/benchmark_postgresql_writes.rb
PG_TEST_DATABASE=campsite_api_perf_review script/test-postgresql runner script/benchmark_postgresql_feeds.rb
PG_TEST_DATABASE=campsite_api_perf_review script/test-postgresql runner script/benchmark_postgresql_maintenance.rb
```

The search seed replaces derived rows only in that explicitly named disposable database. Feed/write fixtures roll back their canonical records. The maintenance benchmark intentionally creates churn in the disposable search table and then runs standard VACUUM. Scripts enforce the test environment and local host, block external traffic where factories are used, and bound SQL statements to 15 seconds. No performance assertion or invented SLA is added to CI.

The two disposable performance databases were removed after evidence capture;
the normal local Campsite test database remains available.
