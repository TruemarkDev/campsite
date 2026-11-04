# PostgreSQL history, failure coverage and API generation

Date: 2026-11-04. Scope: this Campsite repository and its homelab services.
Tracking: `campsite-dbz`, `campsite-v6i`, `campsite-igu`.

## PostgreSQL observations

✅ Native history collection is live. See the [runbook](../deployment/postgresql-query-history.md)
and [redacted artifact](postgresql-query-history-2026-11-04.json).

The first compared window was 1,688.32 seconds, captured at 13:29:44 UTC: 561
application-role statements across 96 shapes, 134.74 ms total execution time.
The highest aggregate-cost shape matched post/comment/membership/user tags:
15 calls, 24.02 ms total, 1.60 ms mean. A post/project-membership/message-thread
shape took 20.98 ms for one call. These are SQL timings, not API percentiles.

This early low-volume window includes application activity and controlled
read-only connection probes. A preceding idle snapshot had no application calls.
It is not a peak-load baseline or evidence of performance improvement. No further
index, memory or global vacuum tuning is justified by these observations alone.
The 101 table snapshots showed 79 estimated dead tuples and no counted autovacuum
event; that establishes neither bloat nor failed maintenance.

## API generation

✅ Broad signature drift no longer reproduces with the existing 13.12.6 generator
and current templates. No dependency upgrade or generated-client hand-edit was
needed. The wrapper now selects test/read-only database access, excludes deployment
credentials, generates/formats in a temporary directory, and leaves tracked
outputs untouched on failure or `--check`. It no longer moves Prettier configuration;
the installed generator uses Biome internally. Invalid public OpenAPI schemas fail.

Repeated no-diff checks passed. Template regressions cover positional path arguments,
query objects, deterministic output and a response-only canary whose sole generated
change is that field. The API workflow adds generated-drift/type checks, these
regressions, environment isolation and metrics-comparison tests.

## Failure behavior

✅ Sync uses a one-minute access lease with a ten-second verification deadline.
Expired-lease messages wait for verification; idle connections are checked too.
Failed/denied verification removes the document subscription. This is bounded
revocation, not instantaneous push invalidation. Human checks use authorized HEAD
requests without document serialization; agent grants use their existing endpoint.
There is no per-keystroke authorization HTTP call.

Human token refresh rechecks note access and updates the actual connection context
for subsequent persistence. Web providers renew every 30 minutes against the existing
one-hour token lifetime. Disconnect/unmount/shutdown clear their timers. Closed
connections cannot recreate a lease. Authenticated queued messages can precede
Hocuspocus's `connected` hook; both entry points share the initial lease.

Tests cover persistence retry with later edits retained, cold replacement loading
unsaved peer state, recovery after SIGKILL without a surviving peer, disconnected
browser edits/reconnect/canonical persistence/reload, and connected-viewer revocation.
The latter verifies the native logical document-close message; a multiplexed socket
may stay open. Recovery of never-persisted edits after every process/client disappears
is not established or promised.

Export tests cover interrupted upload, database failure after upload, duplicate
delivery, one completion notification in those retry paths, and exhausted retries
without overwriting a completed export. They do not certify every integration/job
as exactly-once. Redis broadcast fixtures join both document rooms before asserting
delivery; replacement processes remain cold. Browser cleanup closes its own sockets
before deleting fixture documents. Child environments exclude unrelated credentials.

## Validation and release

✅ Full local Rails baseline: 4,287 tests, 14,041 assertions, zero failures/errors/skips.
Updated focused Rails suites: 30 tests, 106 assertions, zero failures/errors/skips.
The first expanded full run found two controller assertions relying on unspecified
database row order. Those assertions now compare the intended identities; the two
affected suites passed (107 tests, 426 assertions). The corrected full run passed
with seed 18370: **4,291 tests, 14,069 assertions, zero failures/errors/skips**,
in 941.17 seconds.

✅ Entire JavaScript workspace: 391 tests, no skips; nine Turbo tasks ran without
cached results. Counts: config 3, editor 91, sync 67, styled-text 29, web 201. Frontend
CI now runs all workspace test tasks, including previously omitted shared suites.

✅ Eight isolated Chromium scenarios passed in 2.0 minutes without skips/retries.
Template regressions (2), environment isolation (1), metrics comparisons (5), web
lint/types, sync types and focused Ruby lint passed.

✅ Implementation commit `465ddd8` and correction `03ce7ba` were pushed. Its first expanded CI run exposed
two environment/test-lifecycle gaps: the generator's isolated environment omitted
`BUNDLE_APP_CONFIG` used by the Ruby CI image, and existing editor tests left
Tiptap instances alive after jsdom teardown. Corrections preserve that Bundler
configuration path and destroy every editor created by the affected test helpers.
API CI run 33 passed, including generation contracts and the full Rails suite.
Frontend CI run 34 also passed: typechecks, lint, all workspace unit/realtime
tests and production builds. API, sync and web-home were promoted successfully
to the same immutable application revision. PostgreSQL
instrumentation is already live. Existing sidebar/member-search hook edits remain
excluded from this work.

### Release custody

Prepared application revision: `03ce7bab8c030b4ee3803e30c710ebc2d9e122f6`,
built from a clean detached checkout. Target: Quill `192.168.10.32`, existing
homelab API, sync and web-home Kamal configurations, operator `prakash`.
No worker, styled-text, database image or accessory deployment is included.

All three images built successfully and registry manifests were verified:

| Image    | Manifest digest                                                           |
| -------- | ------------------------------------------------------------------------- |
| API      | `sha256:490790c5b014d8a0726abe24da0180544136c24b129610ff9aade497f4d02296` |
| Sync     | `sha256:855d23780dfde25ba319c017eca0943296e49e3483572449d3f0dbce1804e806` |
| Web home | `sha256:f5544c01a0c4fb136e6998e64ee5fd7844cda8055dca3abe569a73cebed5f26e` |

Promotion uses the pinned Ruby/Kamal through `script/campsite-deploy`,
`deploy --skip-push --version=03ce7bab8c030b4ee3803e30c710ebc2d9e122f6`,
with `-c config/deploy.campsite-api.yml`, then `deploy.campsite-sync.yml`, then
`deploy.campsite-web-home.yml`. Per-service runtime secret preflights passed.

Rollback images are retained and verified available in the registry:
API `039d0fe39642f892d73ce0203f12def4bb1c3448`;
sync `40828397481d85996f70ccccc605d369b3e0eb6d_uncommitted_cabf0133f56f6ee1`;
web `c913da23a54989fc3a9ef9135e5783e0a21e4654`.
Use the same wrapper with `kamal rollback <prior-tag> -c <service-config>`.

✅ All three Kamal promotions completed. Independent container/image inspection
confirmed the registry digests above, running state and zero restarts. The web
`/api/build-id` reports the exact revision. API `/up`, sync `/up` and web
`/robots.txt` return HTTPS 200. A probe from the deployed sync container to its
configured API `/up` returned 200. Unauthenticated HEAD on the note sync-state
route returned 401. These probes establish revision/health and transport, not an
authenticated editor workflow.

Post-release Patroni verification: pg-a leader/running, pg-b synchronous
standby/streaming, timeline 38, receive/replay lag zero.

🟡 Fresh authenticated live editor acceptance was not performed: the prior Brave
test window is closed and permission for a new window remains unanswered. The
eight-case isolated Chromium suite passed, including revocation/reconnect, with
no skips or retries. This is the remaining live acceptance gap, tracked as `campsite-th9`.
