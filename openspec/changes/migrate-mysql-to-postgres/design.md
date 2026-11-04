## Context

See `proposal.md` for motivation and the stewardship gate. Current state,
verified against the code on 2026-09-23 (schema `20260828134500`):

- **Adapter:** `trilogy` in `api/config/database.yml`; `mysql2` and
  `planetscale_rails` are also in the Gemfile. `ApplicationRecord`
  `connects_to writing: :primary, reading: :primary_replica`, with the
  `DatabaseSelector` middleware (`config/initializers/multi_db.rb`, 2 s delay).
  The replica was discontinued when Campsite moved to self-hosting (operator,
  2026-09-23); only one MySQL accessory is declared, and no code calls
  `connected_to(role: :reading)` explicitly.
- **Homelab placement** (captured XAPI evidence of 2026-09-22,
  `~/workspaces/2026/homelab/evidence/k3s-capacity-2026-09-22.json`; see
  `notes/ha-image-and-placement.md`): Quill (apps) runs on the `knowhere`
  host of the two-host Asgard pool. Groot (MySQL/Redis) and Mantis
  (Elasticsearch) run on `talokan`, the single-host `vibranium` pool. Vyas is
  the Synology NAS outside XCP-ng. Free memory after the 2 GiB host reserve:
  `talokan` 1.46 GiB (7.46 GiB squeezable under its accepted overcommit
  policy), `asgard` 5.57 GiB, `knowhere` 0 GiB. The ansible inventory drifts
  from this evidence, and the capacity record requires a fresh readback before
  any live admission (task 6.1).
- **Schema:** 95 tables, all `charset: utf8mb4, collation: utf8mb4_0900_ai_ci`;
  244 `unsigned: true` bigints; 0 foreign keys; 17 `json` columns; 12
  `size: :medium` text columns; 6 prefix-length indexes (`length:`); 10 stored
  generated `device_info_*` columns on `product_logs`
  (`json_unquote(json_extract(...))`).
- **MySQL-only SQL call sites:**

  | File | Construct | PostgreSQL form |
  |---|---|---|
  | `app/models/notification_schedule.rb` | `CONVERT_TZ`, `DAYOFWEEK`, `CONCAT(DATE(..),' ',end_time)`, `sunday = 1` | `(:now AT TIME ZONE 'UTC') AT TIME ZONE tz`, `EXTRACT(DOW ...)`, `date + time`, boolean `sunday` |
  | `app/models/scheduled_notification.rb` | `CONVERT_TZ`, `IFNULL`, `INTERVAL n SECOND` | `AT TIME ZONE`, `COALESCE`, `make_interval(secs => ...)` |
  | `app/models/concerns/reactable.rb` | `MAX(IF(...))`, `JSON_ARRAYAGG` | `MAX(CASE WHEN ... END)`, `json_agg` |
  | `app/models/post.rb:895` | `GROUP_CONCAT` | `string_agg(id::text, ',')` |
  | `app/jobs/set_content_updated_at_job.rb` | `JSON_CONTAINS_PATH`, `JSON_OVERLAPS(JSON_KEYS(...))` | jsonb `?` and `?|` |
  | `app/jobs/call_health_job.rb` | `TIMESTAMPDIFF(SECOND, a, b)` | `EXTRACT(EPOCH FROM b - a)` |
  | `lib/cursor_pagination.rb` | relies on MySQL NULLs-first ordering | explicit `NULLS FIRST/LAST` |
  | `app/models/post_view.rb:96` | `upsert_all` = `ON DUPLICATE KEY` on any unique index | `unique_by: %i[post_id organization_membership_id]` |

  About 64 further raw SQL fragments across 33 files in `app/` and `lib/`
  need review for implicit type coercion (e.g. boolean vs integer) and
  case-sensitive `LIKE`.
- **Case handling today:** Devise `case_insensitive_keys = [:email]` downcases
  on save; `User#username` is downcased in `before_save`; `Organization#slug`
  format allows lowercase only; `validates ... uniqueness: { case_sensitive:
  false }` on username and slug. Lookups that bypass Devise (e.g.
  `User.where(email: access_token.info.email)` in the OmniAuth path) currently
  depend on the collation to ignore case.
- **Scale:** last logical dump 19,723,144 bytes compressed; Puma
  `WEB_CONCURRENCY` 2 × `RAILS_MAX_THREADS` 5; pool per process is
  `RAILS_MAX_THREADS × RAILS_MAX_ASYNC_QUERIES` (25); Sidekiq concurrency 1 and 5.
- **Ops:** MySQL 8.4 accessory on Groot (`/srv/campsite-data/mysql`), daily
  compressed logical dump to `starkdrive:/volume1/backups/campsite/` with
  restore rehearsal, `mysqladmin ping` health, `strong_migrations`
  `target_version = "8.4"`.

## Goals / Non-Goals

**Goals:**

- Make every engine-dependent behaviour explicit in code before switching
  engines, so the switch is a configuration and data operation.
- Prove the PostgreSQL build in a realistic, isolated homelab environment for
  at least 30 days while `main` keeps releasing on MySQL.
- A single offline cutover with a mechanical, checksum-verified copy and a
  redeploy-only rollback.
- Survive loss or maintenance of one database member, and recover to any point
  inside the PITR window.

**Non-Goals:**

- Schema improvements during the migration: no foreign keys, no new indexes,
  no column renames, no `json` → native array conversions. They go in later
  proposals so any regression can be attributed to one change.
- Replacing Elasticsearch/Searchkick.
- Online/zero-downtime migration (logical replication, dual writes, CDC).
- Routing reads to replicas.
- High availability for the application tier, Redis or Elasticsearch. Quill,
  Groot and Mantis stay single-host; see D10 for what database HA does and does
  not buy in that topology.

## Decisions

### D1 — Portability lands on `main`; everything else on the branch

Phase 1 is behaviour-preserving and dependency-free, so it merges to `main` in
small PRs and ships in normal releases. That keeps the long-lived
`postgres-migration` branch limited to the adapter, schema, config and
deploy changes, which keeps merges from `main` small over the ≥30-day run.
Engine-specific SQL is expressed through Arel or Ruby where it is cheap, and
otherwise through a small adapter branch (`connection.adapter_name`)
co-located with the query. *Alternative:* keep Phase 1 on the branch too —
rejected; a month of drift across ~11 query sites and 33 raw-SQL files would
make every `main` merge a conflict, and portability bugs would surface only at
cutover.

### D2 — `citext` for identity columns; accept accent sensitivity

`users.email`, `users.username`, `organizations.slug`,
`organization_invitations.email`, `email_bounces.email` become `citext`. This
preserves case-insensitive equality and unique indexes without touching query
code. `citext` ships in the official PostgreSQL image's contrib set.
Accent-insensitivity (`ai`) is deliberately dropped: usernames and slugs are
ASCII-only by validation, and email addresses are compared by case only.
*Alternatives:* `lower()` expression indexes (needs every lookup rewritten to
`lower(col) = lower(?)`); nondeterministic ICU collation (accent control, but
more surprising `ORDER BY`/`LIKE` behaviour). Phase 1 still makes the
OmniAuth-style lookups normalise case explicitly, so SyR-PG-1 also holds on
MySQL independent of collation.

### D3 — Preserve MySQL NULL ordering explicitly

`CursorPagination` emits `NULLS FIRST` for ascending and `NULLS LAST` for
descending (MySQL's native order) on PostgreSQL, and keeps its current
comparator logic. This keeps page order identical across engines (SyR-PG-2).
On MySQL the clause is omitted (unsupported; order is already native).

### D4 — Schema is generated, not hand-written

Keep `db/schema.rb`. Produce the PostgreSQL schema by loading the current
schema with the MySQL-only options stripped (a one-off transform script under
`script/`, not a migration): drop `unsigned`, `charset`, `collation`, index
`length:`; `json` → `jsonb`; `mediumtext` → `text`; generated columns →
`t.virtual ..., as: "device_info->>'browser_name'", stored: true`; D2 columns
→ `citext` with `enable_extension "citext"`. The schema version stays
`20260828134500` (or whatever is current at cutover) so migration history is
continuous. *Alternative:* let pgloader create the schema — rejected; it would
produce types and index names that drift from what Rails regenerates.

### D5 — Ruby copier (`script/pg-copy`), data-only, into the Rails-built schema

*Revised 2026-09-24:* pgloader was the original choice and was rejected after
a rehearsal. pgloader 3.6.10 can't express the generated-column exclusion,
and it crashes in the MySQL 8.4 handshake, because 8.4 always opens with
`caching_sha2_password`.

`script/pg-copy` reads each table from a disposable MySQL restored from the
dump in primary-key batches, using the Gemfile's `mysql2` driver directly (not
ActiveRecord models, so no callbacks). It writes rows into the D4 schema with
PostgreSQL `COPY`. It first runs `TRUNCATE … RESTART IDENTITY CASCADE`, takes
its column lists from the PostgreSQL tables, and skips generated columns
(PostgreSQL recomputes them). It casts `tinyint(1)` to `boolean`, loads JSON
text into `jsonb`, keeps microseconds, copies `schema_migrations` and
`ar_internal_metadata`, and finally `setval`s every sequence to `MAX(id)`. It
prints table names and counts only. At ~20 MB compressed the copy takes
minutes, so the offline window is short.
*Alternatives:* pgloader (above); `mysqldump --tab` CSV plus `COPY` (more
moving parts for type casting); Rails model-level export/import (slower, and
risks callbacks).
Verified on synthetic data (`notes/data-copy-runbook.md`): 100/100 tables
match, 97 sequences are correct, and a tampered row fails parity.

### D6 — Verification by counts and per-table checksums

A script (`script/check-campsite-pg-parity`) compares, per table, `COUNT(*)`
and an order-stable checksum of primary key plus a canonical text rendering of
each row, normalising known representation differences (booleans, JSON key
order via `jsonb` round-trip, datetime precision). It exits non-zero on any
mismatch and records the report path for the release evidence in
`docs/deployment/homelab-production.md`.

### D7 — No PgBouncer initially; explicit `max_connections`

Worst-case pool demand is about 2 Puma workers × 25 + 2 Sidekiq processes × 25
plus console/migration headroom, well under 200. Set PostgreSQL
`max_connections = 200` and revisit only if measured. *Alternative:* PgBouncer
in transaction mode — adds a component and breaks session features Rails uses
(advisory locks for migrations, prepared statements) without a measured need.

### D8 — `strong_migrations`, adapters and the replica role

`StrongMigrations.target_version` becomes `18`; `auto_analyze` stays. The `pg`
gem is added at its latest stable version. On the branch, the discontinued
`primary_replica` role, `DATABASE_REPLICA_URL` and the `DatabaseSelector`
initializer are removed, and `ApplicationRecord` connects to `primary` only;
`DatabaseRoleSwitchable` keeps working because it only selects `:writing`.
`mysql2`, `trilogy` and `planetscale_rails` are removed only after the
post-cutover soak (SyR-PG-11), so rollback never needs a rebuild.

### D9 — Long-lived branch plus an isolated shadow environment

`postgres-migration` is cut from `main` after Phase 1 lands. `main` is
merged into it (merge, not rebase, so shadow-deployed revisions stay
reachable) at least once per `main` release, and the merged revision is
deployed to the shadow environment the same day. New migrations written on
`main` during the run are therefore exercised on PostgreSQL before cutover.

The shadow environment is a separate set of Kamal destinations
(`deploy.campsite-pg-*.yml`) running the branch's API and web images on Quill
under a private hostname (`pg.camp.home`), pointing at the Patroni cluster
(D10). Isolation (SyR-PG-9) is by configuration, not discipline:

- no Sidekiq worker destination, so no queued email, push, webhook or
  integration delivery runs; mailer delivery method `:test`, Pusher and
  outbound integration credentials absent, so request-path side effects fail
  closed;
- its own Redis database number so it never shares queues or caches with
  production;
- Searchkick `index_prefix` of `shadow` so writes never touch production
  indexes (a shadow reindex runs after each refresh);
- a shadow-only object-storage bucket or prefix with write access only there,
  and read-only access to production objects so existing attachments render.

A nightly job restores the latest MySQL daily dump into a disposable MySQL,
runs the `script/pg-copy` copy (D5) into the shadow database, runs parity (D6), and
appends the result to a shadow-run log. That makes every night a full
rehearsal of the cutover copy against real data.
*Alternatives:* logical replication or CDC from MySQL (Debezium, pgloader
continuous) — rejected as a new moving part that would not exist after
cutover; a disposable weekend rehearsal only — rejected, it would miss a month
of `main` migrations and real-data variety.

### D10 — Patroni cluster topology

| Member | Where | Role |
|---|---|---|
| `pg-a` | Groot (`talokan`), `/srv/campsite-data/postgres` | PostgreSQL 18 + Patroni, initial leader, etcd member |
| `pg-b` | new guest VM **pinned to the `asgard` host** of the Asgard pool (2 vCPU, 2 GiB, dedicated data VDI; `knowhere` has no free memory) | PostgreSQL 18 + Patroni replica, etcd member |
| witness | Quill (`knowhere`), a small etcd accessory: the third physical failure domain after `talokan` and `asgard`. Moved from Vyas on 2026-09-26 because Synology Docker is not usable as a Kamal host | etcd member only |

Settings: `synchronous_mode: true` (non-strict), so a commit waits for the
replica when it is up and the leader keeps serving if it is down (SyR-HA-4);
`maximum_lag_on_failover` bounds promotion of a lagging replica; Patroni
`ttl: 30`, `loop_wait: 10`, `retry_timeout: 10`, from which the SyR-HA-2
targets (≤60 s failover, ≤30 s switchover) are derived. These targets are
proposed and SHALL be confirmed or adjusted by the first drill.

What this buys in the current topology, stated plainly (corrected
2026-09-24; an earlier draft wrongly placed Quill on Talokan):

- The application containers run on Quill (`knowhere`); the database leader,
  Redis and Elasticsearch run on `talokan`. If `talokan` fails, Patroni
  promotes `pg-b` on `asgard` and the database stays available, but the
  application is still degraded: Redis (Sidekiq, cache, Rack::Attack) and
  Elasticsearch live on `talokan` and are single-instance. Full availability
  through a `talokan` loss also needs Redis (and search) redundancy, which is
  a separate decision.
- What database HA buys in any case: (1) patching and rebooting either
  database VM or `talokan` without a database outage, via switchover; (2) a
  synchronously replicated copy on different hardware, so a `talokan` disk or
  host loss loses no acknowledged commits; (3) automatic recovery from a
  PostgreSQL process or guest-OS failure.
- If `knowhere` fails, the application is down whatever the database does.

Packaging: one pinned image built from `postgres:18` with Patroni (etcd3
extra) and pgBackRest installed from the PGDG repository, run as a Kamal
accessory per member with host networking; etcd as a pinned upstream image,
one accessory per member. This keeps Kamal as the single control plane for
Campsite stateful services, as `homelab-production.md` requires.
*Alternatives:* Ansible-managed systemd units from the homelab repo — the
conventional Patroni deployment and better at rolling restarts, but it splits
custody of the Campsite database from its other accessories; Spilo — bundles
Patroni and WAL-G, but is Kubernetes-oriented and hides configuration behind
its own env contract. Kamal does not orchestrate rolling restarts, so the
runbook requires `patronictl switchover` before restarting the leader's
accessory.

### D11 — Client routing and backup retention

**Routing:** clients use a libpq multi-host URL,
`postgresql://…@pg-a:5432,pg-b:5432/campsite_production?target_session_attrs=read-write`.
libpq connects to whichever host accepts writes, so no proxy, VIP or extra
component is needed (SyR-HA-3). After a failover, broken connections raise,
Rails reconnects on the next checkout, and Sidekiq retries failed jobs.
*Alternatives:* HAProxy using Patroni's `/primary` REST check — faster
redirection of existing pools, but another process to run and monitor;
vip-manager — needs L2 adjacency between VMs in different pools.

**Backups:** pgBackRest with its repository on the existing
`starkdrive:/volume1/backups/campsite/pgbackrest` namespace, WAL archived
continuously from whichever member leads (`archive_command` runs on the
leader; the repository lock prevents double archiving). Logical `pg_dump -Fc`
runs daily from the replica to keep load off the leader. Proposed retention,
pending operator confirmation:

| Tier | Schedule | Retention | Covers |
|---|---|---|---|
| WAL + base backups (PITR) | full weekly, differential daily, WAL continuous | 5 full backups (`repo1-retention-full=5`, about 35 days of PITR) | "undo the last few weeks to the minute"; spans the 30-day shadow run plus a detection margin |
| Logical dump | daily | 14 dailies | engine-portable restores; independent of pgBackRest's format |
| Logical dump | first of each month | 12 monthlies | slowly discovered corruption, audit, "what did this look like in spring" |
| Milestones | final MySQL dump; first accepted PostgreSQL backup | until a recorded operator decision, minimum 12 months | migration forensics |

Storage is not the constraint: the last compressed dump was 19.7 MB, so the
26 logical dumps total well under 1 GB. The real limit is data you no longer
want to hold. Content a user deletes survives in backups for the whole
retention period, so 12 monthlies means up to a year. Shorten the monthly tier
if that conflicts with what users are told. Restore rehearsal: the logical
dump weekly (automated), and a PITR restore monthly (drill, SyR-PG-7).

Retention is enforced by pgBackRest `expire` and a dump-rotation script
running under a backup identity separate from the database runtime
credential, matching the existing rule that the runtime credential cannot
delete backup history.

## Risks / Trade-offs

- [Mixed-case historical data collides under `citext` uniqueness] → Phase 4
  runs a `GROUP BY lower(col) HAVING count(*) > 1` audit on MySQL data before
  cutover; any hit is resolved by the operator before proceeding.
- [Hidden type coercion in raw SQL, e.g. `sunday = 1` against a boolean] →
  dual-adapter test suite (Phase 2) plus a manual review list of the 64
  fragments; untested fragments get a test before cutover.
- [Case-sensitive `LIKE` changes backfill and search-adjacent matches] →
  review each `LIKE`; current ones match HTML markup substrings where case is
  already fixed, so no change is expected, but each is confirmed.
- [Sort order of text columns differs (collation)] → UI lists that
  `ORDER BY name` are compared on fixture data in Phase 2; accept or pin a
  collation per column.
- [Autovacuum on high-churn tables (`post_views`, `product_logs`,
  notifications)] → default autovacuum at this scale; add table-level settings
  only if bloat is measured.
- [Rollback loses post-reopen writes] → accepted and stated in SyR-PG-6;
  acceptance criteria are checked before reopening writers.
- [Stewardship exception not granted] → Phase 1 still delivers value (explicit
  behaviour, fewer engine assumptions); later phases stay unstarted.
- [Memory is tight on the hosts that matter] → `pg-a` replaces MySQL's
  1 GiB on Groot after cutover rather than adding to it; during the shadow run
  both run on `talokan` (1.46 GiB free after reserve; 7.46 GiB squeezable
  under its overcommit policy). The shadow API/web (~1.3 GiB) must fit
  *inside* Quill's existing allocation, because `knowhere` has no free host
  memory; that inner headroom is not recorded yet. `pg-b` must be pinned to
  the `asgard` host (5.57 GiB free), not placed anywhere in the Asgard pool.
  Task 6.1 does a fresh host and guest readback before any of this is admitted.
- [Redis and Elasticsearch stay single-instance on `talokan`] → database HA
  alone does not keep the application fully available through a `talokan`
  loss (D10). Accepted for this change; revisit with application-tier HA.
- [Shadow side effect leaks to real users or production indexes] → isolation
  is configuration-enforced (D9) and verified by the SyR-PG-9 demonstration
  before the shadow run's day 1.
- [Branch drift over ≥30 days] → Phase 1 on `main` (D1); merge `main` per
  release; a merge that cannot be deployed to shadow the same day pauses the
  30-day clock until it is.
- [Split brain] → etcd majority required for leadership (SyR-HA-1); the
  witness lives outside both database hosts' failure domains.
- [NFS backup mount unavailable] → `archive_command` fails closed, so WAL
  accumulates on the leader and an alert fires; the data VDI is sized for
  several days of WAL at current write rates.
- [Operational load of three new components (Patroni, etcd, pgBackRest) on a
  one-to-two-user platform] → accepted for the exploration; if the shadow run
  shows the cost outweighs the benefit, collapse to a one-member Patroni
  cluster (same tooling, no replica, no witness) without changing the
  migration path.

## Migration Plan

1. **Gate:** record the maintainer's stewardship exception for `pg`,
   PostgreSQL, Patroni, etcd and pgBackRest (in `MAINTENANCE.md` or this change).
2. **Phase 1 on `main`**, then cut `postgres-migration`.
3. **Build** Phases 2–4 on the branch; rehearse the copy on a disposable
   PostgreSQL until parity passes.
4. **Provision** the Patroni cluster (D10) and pgBackRest (D11); prove
   SyR-HA-1/2 and SyR-PG-7 on empty and then rehearsal data. MySQL keeps
   serving production untouched.
5. **Shadow run (≥30 days, D9):** nightly refresh and parity, per-release
   deploys, a switchover and a failover drill, a PITR drill. Readiness review
   against SyR-PG-10.
6. **Window:** stop API, worker and sync writers; take the final consistent
   MySQL dump with checksum; restore into disposable MySQL; `script/pg-copy` into
   the production database on the cluster; run parity (D6).
7. **Switch:** merge the branch to `main`, set `DATABASE_URL` to the
   multi-host URL (D11), deploy; run authenticated reads and compare critical
   counts; then restart worker and sync. Shadow destinations are removed.
8. **Accept:** SyR-PG-5 evidence recorded; first pgBackRest full and logical
   backup taken and restore-rehearsed.
9. **Rollback (before step 8):** redeploy the last MySQL release of `main` with
   the previous `DATABASE_URL`, restart writers against MySQL. The MySQL volume
   is never modified.
10. **Retire (≥30 days after acceptance, SyR-PG-11):** remove MySQL adapters
    and the MySQL accessory declaration; archive the final MySQL dump.
    Deleting the MySQL volume is a separate operator decision.

## Open Questions

- Resolved 2026-09-23: the D11 retention (12 monthly dumps) is accepted by
  the operator.
- Resolved 2026-09-26: the etcd witness runs on Quill (`knowhere`), not Vyas,
  under the operator's "use your judgement" delegation. Synology Docker isn't
  on the SSH `PATH` and needs sudo, so it doesn't fit Kamal accessories. etcd
  members sit on `talokan`, `asgard` and `knowhere`.
- Resolved 2026-09-26: `maximum_lag_on_failover` = 16 MiB. WAL archiving
  stays off (`PATRONI_ARCHIVE_ENABLED=false`) until task 6.6 configures the
  pgBackRest repository and stanza.
- Whether Quill has ~1.3 GiB of inner headroom for the shadow API/web; the
  fresh readback in task 6.1 answers it.
