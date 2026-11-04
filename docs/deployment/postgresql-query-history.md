# Campsite PostgreSQL query history

As built on 2026-11-04. Tracking: `campsite-dbz`.

## Installed state

PostgreSQL 18.6's bundled `pg_stat_statements` 1.12 is loaded on both Campsite
members. Patroni 4.1.5 DCS contains
`postgresql.parameters.shared_preload_libraries: pg_stat_statements`. The
extension exists in `campsite_production`. Verified settings: `save=on`,
`track=top`, `track_planning=off`, `track_io_timing=off`; no pending restart.
No image/package upgrade, memory/pool tuning or vacuum changes were made.

The source template records the default for future bootstraps. Current members
use the DCS setting; their pinned image remains unchanged. PostgreSQL maintains
aggregate history natively and saves it across clean restarts. No custom polling
daemon or scheduler was installed.

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
