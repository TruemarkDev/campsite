## 1. Phase 1 — Portability on `main` (no new dependency)

- [x] 1.1 Add a test pinning current `NotificationSchedule.needs_applying` results for a non-UTC zone and a UTC/local day-boundary case (SyR-PG-4), then rewrite the scope without `CONVERT_TZ`/`DAYOFWEEK`/integer-boolean comparisons; verify the test passes on MySQL
- [x] 1.2 Same for `ScheduledNotification` delivery-window SQL (`CONVERT_TZ`, `IFNULL`, `INTERVAL ... SECOND`); verify with a test covering a non-zero `delivery_offset`
- [x] 1.3 Replace `MAX(IF(...))` and `JSON_ARRAYAGG` in `app/models/concerns/reactable.rb` with portable or adapter-branched SQL; verify the existing reaction serializer/controller tests pass
- [x] 1.4 Replace `GROUP_CONCAT` in `app/models/post.rb:895`; verify the poll tests pass
- [x] 1.5 Replace `JSON_CONTAINS_PATH`/`JSON_OVERLAPS` in `SetContentUpdatedAtJob` and `TIMESTAMPDIFF` in `CallHealthJob`; verify each job's test passes (add one if missing)
- [x] 1.6 Add `unique_by: %i[post_id organization_membership_id]` to `PostView.upsert_all`; verify a test recording the same view in two batches leaves one row (SyR-PG-3)
- [x] 1.7 Add a cursor-pagination test that walks ascending and descending lists across a NULL tail and asserts completeness, no duplicates and NULL placement (SyR-PG-2); make NULL ordering explicit behind an adapter check in `lib/cursor_pagination.rb`
- [x] 1.8 Make identity lookups that bypass Devise normalise case (e.g. the OmniAuth `where(email:)` path, invitation and email-bounce lookups); verify tests with mixed-case input (SyR-PG-1)
- [x] 1.9 Remove `planetscale_rails` and the `ENABLE_PSDB` branches from `database.yml`; verify `bin/rails test` boots/passes a representative model test; `script/setup` was inspected but not run because it replaces local Elasticsearch and reinstalls tooling/dependencies
- [x] 1.10 Review raw SQL fragments across `api/app` and `api/lib` and record each as portable / fixed / needs-test in `notes/raw-sql-review.md`; every needs-test row names a focused MySQL test, including the stale removed-column backfill path
- [ ] 1.11 Run `cd api && bin/rails test` and `bundle exec rubocop` green on MySQL, merge to `main`, and ship in a normal homelab release

## 2. Gate and branch

- [x] 2.1 Record the maintainer's explicit stewardship exception for `pg`, PostgreSQL, Patroni, etcd and pgBackRest (in `MAINTENANCE.md` or this change); stop here if it is not granted
- [ ] 2.2 Cut `postgres-migration` from `main` after 1.11; verify `git merge-base` equals the Phase 1 release revision

## 3. Phase 2 — Dual-adapter test suite (branch)

- [x] 3.1 Add the `pg` gem at the latest stable version (`bundle add pg`) alongside the MySQL adapters; verify `bundle install` succeeds
- [x] 3.2 Add a PostgreSQL `test` configuration selected by an env var (e.g. `DB_ADAPTER=postgresql`) and a local PostgreSQL 18 container recipe; verify `bin/rails db:create db:schema:load` runs against it
- [x] 3.3 Run the full Minitest suite on PostgreSQL and fix failures until green; verify both `bin/rails test` (MySQL) and `DB_ADAPTER=postgresql bin/rails test` pass
- [x] 3.4 Add a migration-atomicity test (SyR-PG-8): a migration that adds a column then raises leaves no column and no version row on PostgreSQL
- [x] 3.5 Remove the `primary_replica` role, `DATABASE_REPLICA_URL` and `config/initializers/multi_db.rb` selector config; connect `ApplicationRecord` to `primary` only (D8); verify the suite passes on both adapters and `DatabaseRoleSwitchable` controllers still write

## 4. Phase 3 — PostgreSQL schema (branch)

- [x] 4.1 Write the one-off schema transform (`script/`) per design D4 and produce the PostgreSQL schema; verify `db:schema:load` on PostgreSQL then `db:schema:dump` round-trips with no diff
- [x] 4.2 Convert the D2 identity columns to `citext` with `enable_extension "citext"`; verify the SyR-PG-1 database-level duplicate test passes on PostgreSQL
- [x] 4.3 Rewrite the 10 `product_logs.device_info_*` generated columns as `->>` stored expressions; verify a `product_logs` insert populates them
- [x] 4.4 Set `StrongMigrations.target_version` per adapter (MySQL `8.4`, PostgreSQL `18`); verify a sample unsafe migration is still blocked on both

## 5. Phase 4 — Data-copy tooling (branch)

- [x] 5.1 Audit MySQL data for case-only duplicates in D2 columns (`GROUP BY LOWER(col) HAVING COUNT(*) > 1`); verify zero rows or an operator-resolved list
- [x] 5.2 Write `script/pg-copy` (design D5: Ruby `COPY` copier, data only, truncate, sequence reset, `tinyint(1)` → boolean casts, generated columns skipped; pgloader rejected on MySQL 8.4); verify a copy from a restored daily dump into a disposable PostgreSQL completes without errors
- [x] 5.3 Write `script/check-campsite-pg-parity` (design D6); verify it passes on the rehearsal copy and fails when a row is deliberately altered
- [ ] 5.4 Verify post-load sequences: inserting one row into every table gets an id above the migrated maximum (SyR-PG-5)

## 6. Phase 5 — Patroni cluster and backups

- [x] 6.1 Re-verify host and guest placement (Quill on `knowhere`, Groot/Mantis on `talokan`) and run the homelab capacity admission for `pg-a` on Groot, shadow API/web inside Quill, and a 2 GiB `pg-b` pinned to the `asgard` host; record the evidence in `~/workspaces/2026/homelab`
- [x] 6.2 Provision the `pg-b` guest VM with a dedicated data VDI via the homelab repo's existing guest-provisioning path; verify SSH, Docker and Kamal reachability
- [x] 6.3 Build and pin the `postgres:18` + Patroni + pgBackRest image (PGDG packages, latest stable); verify `patroni --version`, `pgbackrest version` and PostgreSQL 18 in the image
- [x] 6.4 Add etcd accessories on `pg-a`, `pg-b` and the witness host, and Patroni accessories on `pg-a` and `pg-b` (D10 settings); verify `patronictl list` shows one leader, one sync standby, and etcd reports three healthy members
- [ ] 6.5 Configure clients with the multi-host `target_session_attrs=read-write` URL (D11); verify a Rails console session reports `pg_is_in_recovery() = false` whichever member leads (SyR-HA-3)
- [x] 6.6 Configure pgBackRest (repo on `starkdrive:/volume1/backups/campsite/pgbackrest`, weekly full, daily diff, `repo1-retention-full=5`) and continuous WAL archiving; verify `pgbackrest check` and `pgbackrest info` on both members
- [ ] 6.7 Add the daily logical `pg_dump -Fc` with checksum from the replica (falling back to the leader), 14-daily and 12-monthly rotation under a separate backup identity (D11); verify rotation on a dry run
- [ ] 6.8 Add alerts for leader change, replica down or lagging, etcd quorum loss, WAL archive failure and backup age; verify each fires once in a drill
- [x] 6.9 Drill SyR-HA-1/2/4 on rehearsal data: switchover, hard power-off of the leader VM, replica stopped, etcd minority lost; record timings and outcomes
- [ ] 6.10 Drill SyR-PG-7: logical restore, PITR to a timestamp before a deliberate delete, archiving continuity across a failover; record evidence
- [ ] 6.11 Add PostgreSQL, Patroni, etcd and backup secrets to `.kamal/campsite-secrets` and `script/check-campsite-kamal-secrets`; verify `mise -E deploy exec -- script/check-campsite-kamal-secrets` passes

## 7. Phase 6 — Shadow run (≥30 days)

- [ ] 7.1 Add shadow Kamal destinations (`deploy.campsite-pg-*.yml`) for API and web on Quill under `pg.camp.home`, with no worker destination, mailer `:test`, no Pusher/integration credentials, a separate Redis DB, Searchkick `index_prefix` `shadow`, and a shadow-only object-storage write scope (D9); verify the SyR-PG-9 scenarios before day 1
- [ ] 7.2 Add the nightly refresh job (restore latest MySQL dump → disposable MySQL → `script/pg-copy` → parity → shadow reindex) appending to a shadow-run log; verify one full run end to end
- [ ] 7.3 For every `main` release during the run: merge `main` into the branch, deploy it to shadow the same day, and log the revision; verify the log has one entry per release
- [ ] 7.4 Run authenticated browser checks weekly on the shadow environment (sign-in with mixed-case email, post list pagination, notification schedule, upload, search); log results
- [ ] 7.5 Readiness review against SyR-PG-10 (≥30 days, per-release deploys, parity history, HA and PITR drills); verify every item is met or cutover is postponed

## 8. Phase 7 — Cutover

- [ ] 8.1 Stop API, worker and sync writers; take the final checksummed MySQL dump; record schema version and critical counts
- [ ] 8.2 Restore into disposable MySQL, run `script/pg-copy` into the production database on the Patroni cluster, run parity; verify zero mismatches (SyR-PG-5)
- [ ] 8.3 Merge the branch to `main` (the operator's named target), set `DATABASE_URL` to the multi-host URL, deploy API, run authenticated reads; verify counts match, then deploy worker and sync
- [ ] 8.4 If any check in 8.2–8.3 fails, redeploy the last MySQL release with the previous `DATABASE_URL` and verify the app serves from MySQL with pre-cutover counts (SyR-PG-6)
- [ ] 8.5 Take and restore-rehearse the first production pgBackRest full and logical backup; remove the shadow destinations; record acceptance evidence in `docs/deployment/homelab-production.md`
- [ ] 8.6 Update `docs/deployment/homelab-production.md` (service table, Patroni runbook incl. switchover-before-restart, backups and retention, rollback), `script/setup`, `script/bootstrap` and `AGENTS.md`; verify no doc describes MySQL as current

## 9. Retirement (≥30 days after acceptance)

- [ ] 9.1 Confirm SyR-PG-11 soak elapsed; remove `mysql2` and `trilogy`, MySQL branches in code and config, and the MySQL accessory declaration; verify `bin/rails test` green on PostgreSQL only
- [ ] 9.2 Archive the final MySQL dump with checksum as a milestone backup; leave volume deletion to a separate recorded operator decision
- [ ] 9.3 Open follow-up proposals: foreign keys, partial/GIN indexes, PostgreSQL search vs Elasticsearch, and application-tier HA if database HA proved worthwhile
