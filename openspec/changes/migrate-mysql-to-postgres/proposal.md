## Why

Campsite's only relational store is a MySQL 8.4 accessory on Groot, inherited
from a PlanetScale-era design. The application silently depends on two MySQL
behaviours — the case- and accent-insensitive `utf8mb4_0900_ai_ci` collation on
all 95 tables and MySQL's NULLs-first sort order in cursor pagination — plus
about eleven MySQL-only SQL call sites. That lock-in blocks rollback-safe
(transactional) schema migrations, PostgreSQL-native high availability and
point-in-time recovery, and the option to evaluate PostgreSQL full-text/trigram
search as a replacement for the separate Elasticsearch host (Mantis), whose
recovery is already a documented burden (`docs/deployment/elasticsearch-recovery.md`).

The read replica that `database.yml` still declares was discontinued when
Campsite moved to self-hosting; `DATABASE_REPLICA_URL` is vestigial. The
replacement redundancy is a Patroni-managed PostgreSQL cluster in the homelab.

The dataset is small (compressed logical dump ≈19.7 MB; 46 users, 768 posts,
5,230 messages at the last release), so an offline cutover with full
verification is cheap. The expensive part is correctness, not data volume.

**Stewardship gate (resolved 2026-09-23):** the maintainer ended stewardship
mode and granted this change, so adding `pg`, PostgreSQL, Patroni, etcd and
pgBackRest is authorized (`MAINTENANCE.md` status note).

## What Changes

- **Branching and parallel run.** Work happens on a long-lived branch
  (`postgres-migration`). `main` keeps releasing to the MySQL homelab
  environment throughout. The branch is deployed as a separate, isolated
  **PostgreSQL shadow environment** in the homelab, refreshed from the MySQL
  backups and kept in step with every `main` release, for **at least 30
  days** before cutover.
- **Phase 1 — Portability on MySQL (no new dependency).** Rewrite the MySQL-only
  SQL (`CONVERT_TZ`, `DAYOFWEEK`, `IFNULL`, `IF`, `GROUP_CONCAT`,
  `JSON_ARRAYAGG`, `JSON_OVERLAPS`, `JSON_CONTAINS_PATH`, `TIMESTAMPDIFF`);
  make NULL ordering in `lib/cursor_pagination.rb` explicit; add `unique_by:`
  to `PostView.upsert_all`; make case-insensitive identity lookups explicit.
- **Phase 2 — Dual-adapter test suite** (MySQL 8.4 and PostgreSQL 18).
- **Phase 3 — PostgreSQL schema** (types, `citext` identity columns,
  generated columns, `jsonb`).
- **Phase 4 — Data-copy tooling** (Ruby `COPY`-based copier, sequence reset, parity checker).
- **Phase 5 — Patroni cluster and backups.** Two PostgreSQL 18 members managed
  by Patroni on separate physical hosts, a three-member etcd quorum,
  leader-only client routing, pgBackRest WAL archiving with point-in-time
  recovery, and daily logical dumps.
- **Phase 6 — Shadow run (≥30 days)** with nightly refresh and parity,
  per-release deploys, failover and restore drills.
- **Phase 7 — Offline cutover**, with the untouched MySQL volume kept as
  rollback custody for at least 30 days.
- **Removals:** the discontinued `primary_replica` role and
  `DATABASE_REPLICA_URL`, `planetscale_rails`, the `ENABLE_PSDB` switch, and —
  after the post-cutover soak — `mysql2` and `trilogy`.
- **Out of scope (separate proposals):** foreign keys, partial/GIN indexes,
  read-replica query routing, and replacing Elasticsearch with PostgreSQL
  search.

No user-facing behaviour changes. Any observable difference after cutover
(login/email matching, list order, pagination) is a defect.

## Capabilities

### New Capabilities

- `database-platform`: Behavioural invariants the relational store must hold
  across engines — case-insensitive identity matching, stable cursor
  pagination, upsert semantics, time-zone scheduling — plus verified,
  reversible cutover, the isolated parallel run, and backup/restore
  obligations.
- `database-high-availability`: Leader election, failover and switchover,
  client routing to the current leader, and replication-lag bounds for the
  Patroni-managed PostgreSQL cluster.

### Modified Capabilities

None.

## Impact

- `api/Gemfile`: add `pg` (latest stable; **new dependency**, needs the
  stewardship exception); later remove `mysql2`, `trilogy`, `planetscale_rails`.
- `api/config/database.yml`, `app/models/application_record.rb`,
  `config/initializers/multi_db.rb` (replica role removed), `api/db/schema.rb`,
  `api/config/initializers/strong_migrations.rb`, Searchkick index-prefix
  configuration.
- Application code: `app/models/notification_schedule.rb`,
  `app/models/scheduled_notification.rb`, `app/models/concerns/reactable.rb`,
  `app/models/post.rb`, `app/models/post_view.rb`,
  `app/jobs/set_content_updated_at_job.rb`, `app/jobs/call_health_job.rb`,
  `lib/cursor_pagination.rb`, plus a review of ~64 raw SQL fragments across
  33 files in `app/` and `lib/`.
- Deployment: new Kamal destination files for the shadow environment and for
  the Patroni, etcd and pgBackRest accessories; `config/deploy.campsite-api.yml`,
  `config/deploy.campsite-worker.yml`, `.kamal/campsite-secrets`,
  `script/check-campsite-kamal-secrets`, `script/setup`, `script/bootstrap`,
  `docs/deployment/homelab-production.md`.
- Homelab capacity: one new guest VM (the second PostgreSQL member) pinned to
  the `asgard` host, not `talokan` where Groot runs, and a small etcd witness
  on Quill (`knowhere`) as the third failure domain. The homelab inventory and capacity records live in
  `~/workspaces/2026/homelab`.
- Elasticsearch/Searchkick: production indexes unchanged; primary keys are
  preserved so they stay valid. The shadow environment uses its own index prefix.
- Downtime: one planned offline window for API, worker and sync writers.
