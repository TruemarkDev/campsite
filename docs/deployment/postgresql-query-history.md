# Campsite PostgreSQL query history

Instrumentation as built on 2026-11-04 (`campsite-dbz`); native daily cron added
on 2026-11-05 (`campsite-a08w`).

## Installed state

PostgreSQL 18.6's bundled `pg_stat_statements` 1.12 is loaded on both Campsite
members. Patroni 4.1.5 DCS contains
`postgresql.parameters.shared_preload_libraries: pg_stat_statements`. The
extension exists in `campsite_production`. Verified settings: `save=on`,
`track=top`, `track_planning=off`, `track_io_timing=off`; no pending restart.
No image/package upgrade, memory/pool tuning or vacuum changes were made.

The source template records the default for future bootstraps. Current members
use the DCS setting; their pinned image remains unchanged. PostgreSQL maintains
aggregate history natively and saves it across clean restarts. No custom polling daemon was installed. Daily exports now use the hosts' existing
Debian cron services as described below.

The module is server-wide and retains its internal normalized statement text.
The collector filters to `campsite_production` and application role
`campsite_app`. Reports export no SQL text, bind values, credentials or customer
records. Relation tags use a fixed table-name list; they are hints, not a SQL parser.

## Read-only collection

```sh
python3 -B script/postgresql-metrics.py --output /tmp/campsite-query-baseline.json
# Later, after normal traffic:
python3 -B script/postgresql-metrics.py \
  --baseline /tmp/campsite-query-baseline.json \
  --output /tmp/campsite-query-next.json
```

Files are created exclusively with mode 0600; existing files are never overwritten.
The collector uses existing operator SSH access, BatchMode, fixed member/container
names and container-local `psql` as `postgres`. SQL runs in a read-only transaction
with ten-second statement and one-second lock timeouts. It never resets counters
or performs maintenance.

Default: `pg-a`, `192.168.10.33`. Use `--member pg-b` when `192.168.10.35` is primary.
Standbys and unexpected databases are rejected. Start a fresh baseline after a
leadership change. Comparison rejects changed member, database, recovery role,
postmaster start, application role OID, statistics reset or statement eviction,
and decreasing counters. Query IDs remain strings, preserving 64-bit precision.

Reports include per-query counts/execution times, cache/temp/WAL counters and
table/index maintenance/size snapshots. Interval means use deltas, not cumulative
means. These aggregates do not provide request percentiles or rendering latency.

```sh
python3 -B -m unittest discover -s script/tests -p 'test_postgresql_metrics.py'
```

## Representative measurement plan

The first comparison covered only about 28 minutes and 561 application statements.
It is not enough evidence for broad database tuning. Use the existing collector
over roughly a week of ordinary activity, including a busy period, search/feed
navigation, note edits, uploads and any normally scheduled jobs/exports. If that
week is idle, extend the window instead of treating synthetic probes as normal load.

Take an initial snapshot, then another after a busy session and approximately once
per day. Store the redacted JSON in a private operator directory outside Git;
choose distinct filenames because the collector never overwrites existing ones.
Compare the final snapshot with the start of the same uninterrupted interval.
Use a fresh baseline if the collector rejects a reset, restart, failover or eviction;
retain the earlier files as separate intervals rather than subtracting incompatible
counters. Do not reset `pg_stat_statements` or run maintenance just to get a sample.

Rank query shapes by interval total execution time, calls, mean execution time,
temp I/O and WAL, alongside table growth/dead-tuple and maintenance trends.
Application-role statement totals do not measure request latency or user experience.
Investigate a small number of the highest-impact shapes; inspect exact SQL only
inside an authorized database session, keeping SQL text and bind/customer values
out of the exported report. Reproduce their plans on representative disposable
data, then validate one bounded index/query change at a time against the same
workload. A low-frequency slow statement and a cheap high-frequency statement
need different remedies.

No new collector daemon is needed: PostgreSQL already accumulates statistics.
Daily snapshots are now scheduled on the existing host cron services. Manual
snapshots remain useful after a particularly busy session; use separate output
filenames so the scheduled daily files remain idempotent.

## Scheduled collection — 2026-11-05

Daily collection is installed on both PostgreSQL members:

| Member | Host                  | Schedule     |
| ------ | --------------------- | ------------ |
| pg-a   | Groot `192.168.10.33` | `15 7 * * *` |
| pg-b   | `192.168.10.35`       | `15 7 * * *` |

Both hosts use `Asia/Kathmandu`; Debian cron schedules against that host timezone.
The command also sets `TZ=Asia/Kathmandu` for daily filenames. Both cron services
were active and enabled at installation. Scheduling needs no new daemon, package,
LLM job, operator SSH key distribution or PostgreSQL restart. Debian's existing
`cron` package is `3.0pl1-197`, matching the configured repository candidate;
Python is `/usr/bin/python3` (3.13.5). `flock`, `timeout` and `systemd-cat` are
existing OS tools. OS package updates remain owned by normal host maintenance.

Source entries: `config/cron/postgresql-metrics-pg-a` and
`config/cron/postgresql-metrics-pg-b`. On each host:

- `/etc/cron.d/campsite-postgresql-metrics`: root-owned, mode 0644.
- `/opt/campsite-postgresql-metrics/`: root-owned program, SQL and SHA-256 manifest.
- `/var/lib/campsite-postgresql-metrics/`: owned by `prakash`, mode 0700.
- Dated JSON snapshots and `latest.json`: mode 0600, atomic publication.

The job runs as the existing `prakash` operator and accesses only the fixed local
PostgreSQL container through Docker. Manual SSH collection remains supported.
A standby records `skipped_standby` without exporting a raw snapshot; the primary
collects once per local calendar day. Running on both hosts follows a primary
change without copying SSH credentials or exporting standby counters.

The native `flock` command prevents overlap. Native `timeout` limits the command
to 60 seconds with a five-second kill grace; the existing SQL and subprocess
timeouts remain in place. Output goes to the system journal under
`campsite-postgresql-metrics`; stderr has error priority. Cron email is disabled.
There is no automatic email/chat alert configured by this change.

Dated snapshots retain the most recent 30 local dates per member. Pruning only
matches the collector's own canonical snapshot filenames. First collection makes
a baseline. Later comparable days include interval deltas; resets, restarts,
evictions or an invalid previous baseline produce `baseline_reset` while preserving
new raw counters. They do not manufacture a comparison across incompatible stats.
`already_collected` means the same-day file was validated and retained, not that a
fresh database probe ran. A failed run records its exception type in `latest.json`
and exits nonzero. These are metrics snapshots, not application backups.

Read status without exposing SQL or credentials:

```sh
cat /var/lib/campsite-postgresql-metrics/latest.json
sudo -n journalctl -t campsite-postgresql-metrics --since '2 days ago' --no-pager
```

An old receipt indicates the need to inspect cron and the journal; these files do
not constitute an external alerting service. Raw files live separately on each
member. Retrieve the applicable files through existing operator SSH access for a
weekly comparison; keep intervals separate when statistics are incompatible.

Seventeen focused Python tests passed, including comparison, local transport,
standby rejection/skip, private files, daily idempotence, atomic publication,
retention, failed receipts and fresh baselines. The installed program SHA-256 is
`51f217725bf7d720e3ae5e881fe282069394b219d8998db3fcdd14bbd2256702`.
This is a working-tree deployment based on `4a44098`, with exact installed file
hashes recorded in `/opt/campsite-postgresql-metrics/manifest.json`.

✅ Native cron executed the matching commands on both hosts at 2026-11-05 08:35
Nepal time. pg-a produced a baseline (captured 02:50:01 UTC); pg-b recorded
`skipped_standby`. Primary JSON was 238,724 bytes, with no statement SQL-text
fields exported. Snapshot/receipt modes were verified 0600 and directories 0700.
The journal independently recorded both runs. Temporary validation cron entries
were removed; the permanent entries remain active. The next daily run is
2026-11-06 at 07:15 Nepal time. A future 07:15 execution is not yet observed.

Rollback/pause: remove only `/etc/cron.d/campsite-postgresql-metrics` on each
member with `sudo -n rm -f /etc/cron.d/campsite-postgresql-metrics`. Cron detects
that automatically; do not restart the database or remove its extension.
Retain `/var/lib/campsite-postgresql-metrics` for analysis unless its deletion is
explicitly requested. Reinstallation uses native `install` for the program/SQL and
the matching member's checked-in cron file; preserve ownership and modes above.

## Rollout evidence and rollback

Backup checkpoint `20261031-194502F_20261104-125119I` and WAL archive check passed.
Initial topology: `pg-a` primary, `pg-b` synchronous standby, zero lag, timeline 36.
No preload library was configured; the matching module library was already present.

The DCS change ran on Groot through existing SSH access:

```sh
docker exec -u postgres campsite-pg-a patronictl \
  -c /run/patroni/patroni.yml edit-config campsite \
  --pg shared_preload_libraries=pg_stat_statements --force
```

The standby restarted and rejoined synchronously. API ingress entered native Kamal
maintenance and both worker roles stopped gracefully. Planned switchover to `pg-b`
restarted/demoted `pg-a`, loading its setting without another restart. The extension
was created in the Campsite database on the primary. Planned switchover restored
`pg-a` primary and `pg-b` synchronous standby on timeline 38, zero lag. Workers
restarted at their existing revision; API traffic resumed. HTTPS health and an
application-role read-only connection probe passed.

Rollback removes the DCS preload parameter and repeats the same standby-first
restart/planned-switchover sequence. Never restart both members together. Coordinate
extension/reporting-tool removal afterward; application code does not depend on
the extension. Preserve data volumes and backup custody. No rollback was needed.

References: [PostgreSQL 18](https://www.postgresql.org/docs/18/pgstatstatements.html),
[Patroni dynamic configuration](https://patroni.readthedocs.io/en/latest/dynamic_configuration.html).
