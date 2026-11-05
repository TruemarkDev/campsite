# Campsite homelab platform

Current application search uses PostgreSQL `search_documents`; the API and
workers were cut over and verified as recorded in the
[search release evidence](../reviews/postgresql-search-release-2026-11-04.md).
Elasticsearch is no longer needed by the application. The Mantis VM and its disks are removed from Xen. Older Elasticsearch recovery
instructions below apply only to the former deployment and must not be used
for the current application.

Status (2026-10-30): 🟡 `camp.home` API and workers use the two-node Patroni
PostgreSQL cluster. The final paused-writer MySQL dump restored into a disposable
MySQL container and copied to Patroni with parity across 100 tables and 97
sequences. The API and both worker roles run the merged `main` revision
`91de4dfc92824547e503fe1294a2ba836161019f`. A controlled switchover
from `pg-b` to `pg-a` succeeded; the deployed API connected to the new writable
leader, and `pg-b` rejoined as a synchronous standby with zero replay lag.
`camp.home`, API, sync, styled-text, and HTML-to-image routes are live; the
image service returned a valid PNG from `/image`. A post-cutover pgBackRest
full backup `20261030-150749F`, WAL check, and isolated read-only restore passed.
Authenticated browser flow,
WebSocket mutation, and browser upload round trip remain
unproven. Historical MySQL staging and rollback evidence remains below; it does
not describe the current database writer.

This is the LAN-only `camp.home` staging platform. Kamal is the
deployment control plane for every Campsite application runtime and stateful
accessory. The split is by deploy configuration because Kamal deploys one
application image per configuration; it is not a return to hand-managed SSH
deployments.

## Service placement

| Component                  | Kamal unit  | Host                                        | Ceiling           | Persistence              | Health signal                      |
| -------------------------- | ----------- | ------------------------------------------- | ----------------- | ------------------------ | ---------------------------------- |
| Next.js web                | application | Quill `192.168.10.32`                       | 512 MiB           | none                     | HTTP `/robots.txt`                 |
| Rails API/auth             | application | Quill                                       | 768 MiB           | none                     | HTTP `/up`                         |
| Sidekiq/export worker      | application | Quill                                       | 512 MiB           | none                     | process plus queue latency         |
| Sync server                | application | Quill                                       | 256 MiB           | none                     | HTTP `/up` and WebSocket probe     |
| Styled-text server         | application | Quill                                       | 256 MiB           | none                     | HTTP `/up`                         |
| HTML-to-image              | application | Quill                                       | 512 MiB           | none                     | HTTP `/up` and PNG render probe    |
| PostgreSQL 18/Patroni      | accessory   | Groot `192.168.10.33`, pg-b `192.168.10.35` | host managed      | persistent host volumes  | leader and sync standby, SQL probe |
| Redis                      | accessory   | Groot                                       | 384 MiB           | persistent AOF volume    | `redis-cli ping`                   |
| S3-compatible object store | external    | Vyas authoritative                          | provider-owned    | existing durable storage | upload/download probe              |

Groot uses a dedicated VDI at `/srv/campsite-data` for PostgreSQL and Redis.
The retired MySQL data directory and Mantis VDI are absent.

Quill is the only application runtime host. Groot and pg-b host the Patroni
database pair, with an etcd member on Quill for quorum. Groot runs Redis. The final MySQL migration archive remains on Vyas. Vyas remains the authoritative object-storage and pgBackRest host.
Only PostgreSQL has a high-availability pair; application services, Redis,
and object storage do not have equivalent failover here.

The listed ceilings total 4.6 GiB on Quill before Kamal proxy and system
overhead. Quill's dedicated `quill-runtime` VDI is 256 GiB, mounted at
`/srv/campsite-runtime`, with DockerRootDir
`/srv/campsite-runtime/docker`; its original 3 GiB boot VDI was not changed.

## Kamal layout

The staging declaration is split into these destination-specific files
while sharing host, registry, secret, and network conventions:

| File                                | Responsibility                                                                          |
| ----------------------------------- | --------------------------------------------------------------------------------------- |
| `deploy.campsite-web-home.yml`      | LAN-only Next.js web                                                                    |
| `deploy.campsite-api.yml`           | Rails web, Patroni PostgreSQL client, Groot Redis, and Mantis Elasticsearch declaration |
| `deploy.campsite-worker.yml`        | Sidekiq only; explicit writer-custody activation                                        |
| `deploy.campsite-sync.yml`          | Sync server                                                                             |
| `deploy.campsite-styled-text.yml`   | Styled-text server                                                                      |
| `deploy.campsite-html-to-image.yml` | HTML-to-image                                                                           |

The Rails web and Sidekiq services deliberately do not share a Kamal config.
Deploying `deploy.campsite-api.yml` therefore cannot start a queue consumer.
`deploy.campsite-worker.yml` reuses the Rails image. Writer custody has moved to
the homelab worker, while its scheduler remains disabled by default and requires
a separate promotion step.

### Canonical staging identities

Every active Kamal application and accessory declaration uses `staging` as its
environment identity. The web image compiles only the private `.home` origins:

| Runtime             | Kamal service                    |
| ------------------- | -------------------------------- |
| Rails API/auth      | `campsite-api-staging`           |
| Sidekiq             | `campsite-worker-staging`        |
| Private Next.js web | `campsite-web-home-staging`      |
| Sync                | `campsite-sync-staging`          |
| Styled text         | `campsite-styled-text-staging`   |
| HTML-to-image       | `campsite-html-to-image-staging` |

Private HTTPS `*.camp.home` hostnames are the only active browser and service
interfaces. The public `camp*.polo-apps.com` tunnel routes are absent and the
public web service is stopped. Groot's `/srv/campsite-data` and Mantis'
`/srv/elasticsearch-data` filesystems are intentionally distinct from the
untouched Odin source volumes.

Browser uploads use `https://s3.camp.home`, and media reads use
`https://cdn.camp.home`. Both routes remain on the LAN and target the
authoritative Vyas Garage data. Rails uses the same private S3 endpoint for
server-side access and presign generation.

✅ The checked-in service identities and target hosts are amended. Groot's
MySQL/Redis and Mantis' fresh ES are provisioned and restart-verified; all
Quill application containers are running the exact immutable tags recorded in
the release evidence below. Old Odin containers and their source volumes
remain stopped and recoverable; they were not deleted.

### Voice-note runtime gate

Voice-note processing runs inside the Sidekiq container, so installing speech
tools only on Quill does not satisfy the runtime contract. The immutable
worker image SHALL contain `whisper-cli`, its separately supplied GGML model,
and `edge-tts` (Verification: Inspection); see `api/README.md` for environment
names and smoke tests.
⚠️ The target worker is running and a database-only `PostIndexHealthJob` was
consumed successfully, but voice-note speech-tool/model smoke tests have not
been demonstrated. Voice-note processing remains a separate promotion gate and
the check SHALL run before enabling that workload (Verification: Demonstration).

All application images are immutable and tagged with the exact Git revision.
Custom amd64 application images are built only on `builder.home` and deployed
to Quill. The Elasticsearch guest pulls Elastic's pinned upstream amd64 image
directly, so it is not an application builder or private-registry target. The
Kamal declarations use `builder.home:5555`; the builder registry must be
reachable from both builder and Quill and must not be represented as
`localhost:5555`. The live registry is intentionally anonymous on the private
Servers VLAN because the remote BuildKit driver cannot consume its HTTP
basic-auth challenge. UFW permits port 5555 only from the builder and the
three staging guests. Credential values are never tracked or written into this
repository; the retained registry credential custody is not used by Kamal.

Runtime base images and Elasticsearch are also pinned to immutable manifest
digests. Node-based images use the repository's declared Node 24.19.0 runtime;
all application processes run as unprivileged users. Updating a base image or
Elasticsearch therefore requires an explicit digest refresh and rebuild rather
than silently following a mutable registry tag.

### Elasticsearch 9.5 migration (✅ fresh target deployed and rebuilt)

The declared image moved from 8.8.0 to 9.5.0. Elastic does not support a direct
rolling upgrade from 8.8 to 9.x — the documented path is 8.8 → 8.19 (the last
8.x minor) → 9.x, and indices created by 7.x are unreadable in 9.x.

Campsite's Elasticsearch holds only derived search indices, every one of which
is rebuildable from MySQL, so the recommended path skips the ladder entirely:

1. Stop the accessory and the workers that write to it.
2. Mount the fresh Mantis `/srv/elasticsearch-data` filesystem as the
   Elasticsearch data path —
   do not carry Vyas/Synology data or perform an unsafe version migration.
3. `kamal accessory boot elasticsearch` on the 9.5.0 digest, and wait for the
   cluster-health check to report green.
4. Reindex from the application against the live database — from `api/`,
   `bin/rails searchkick:reindex:all`, or one model at a time with
   `bin/rails searchkick:reindex CLASS=Post` (the searchkick-indexed models are
   `Post`, `Note`, and `Call`).
5. Verify before re-enabling search-dependent traffic, comparing each index
   against the rows searchkick actually imports (`search_import`, not a raw
   table count — the models scope what they index):

   ```ruby
   [Post, Note, Call].each do |m|
     puts "#{m.name}: es=#{m.search_index.total_docs} db=#{m.search_import.count}"
   end
   ```

The pinned image digest is
`sha256:8818ab9af72d7482e38a9d6f0454d5ee667564a25bbdc42360c0f9b8f8f72fc5`.
✅ Mantis health, restart persistence, and green/no-unassigned state are
verified against the pinned image and fresh data filesystem. Reindex parity is
`Post 768/768`, `Note 68/68`, and `Call 0/0` (database/search documents), and a
Searchkick wildcard query returned 768 total results. The declared
`config/elasticsearch/staging-index-template.json` applies zero replicas to
future Searchkick indices; without it, a healthy single-node cluster remains
yellow because each unassignable replica has no second node.

Preserving the existing volume instead would require the 8.19 intermediate hop
first; there is no reason to take that path for a rebuildable index.

Deploys use Kamal commands from the operator workstation. SSH is Kamal's
transport, not an independent deployment procedure. Direct host commands are
reserved for provisioning prerequisites and break-glass recovery and require a
separate mutation approval.

The API role starts with `bin/rails db:migrate` and starts Puma only after the
migrations succeed. Kamal therefore checks and advances the schema from the
exact image version being released before its health check can pass or proxy
routing can change. A failed migration leaves the prior healthy API routed.
Schema rollback remains an explicit operator decision because it can destroy
data written by a newer release.

## Release and migration evidence

### 2026-09-24: PR #2 (PostgreSQL migration Phase 1), `b3b28f9`

- Deployed `deploy.campsite-api.yml`, then `deploy.campsite-worker.yml`, from a
  clean detached worktree at the merged Forgejo revision `b3b28f9` (images tagged
  with the full SHA and no `_uncommitted` suffix). The previous runtimes were
  `40828397…_uncommitted_…`; those images stay available for `kamal rollback`.
  Web, sync, styled-text and html-to-image were not redeployed; they have no
  changes in this release.
- Preflight: `script/check-campsite-kamal-secrets` exit 0. No pending
  migrations (Beads Board `20260828130000` was already applied); schema stays
  `20260828134500`.
- After deploy: api/auth `/up` 200; Sidekiq 2 processes, all queues empty;
  search check 768/768 posts and 69/69 notes, known-record searches pass.
  Pre-existing and unrelated: 5 `OrganizationMailer#bundled_notifications`
  retries (SMTP `EOFError`/`SMTPFatalError`) and 5 old dead jobs.
- Same day, Quill was raised from 4 to 6 GiB with a clean shutdown and start
  (about 1 minute of downtime for everything on Quill), for the planned PG
  shadow run. All 11 containers returned and every Campsite `/up` endpoint
  returned 200. Evidence: `~/workspaces/2026/homelab/evidence/quill-memory-2026-09-24.md`.

The source VM was Cosmo/Odin (`192.168.10.7`); its Campsite API, worker, sync,
MySQL, and Redis writers are stopped and its source volumes remain untouched.
The source MySQL was 8.4.11, schema `20260828134500`, and the compressed
logical dump was 19,723,144 bytes with SHA-256
`7aeb06f1d14eb8de5277b180b01a37bb7944dd7f8ba324cb53902a2fbc1bd8cf`.
Source critical counts were users 46, organizations 8, memberships 26, posts
768, notes 68, calls 0, messages 5,230, webhooks 2, and events 5,950. The
dump was restored into a disposable MySQL before the final Groot restore; the
final target reports users 46, posts 768, notes 68, and schema
`20260828134500`. Rails reads from the running API returned the same counts.

The source Redis AOF rehearsal recorded DB0/1/2/3 as 0/60/0/0; its base-RDB
and manifest checksums are retained with the recovery artifacts. The final
Groot Redis reports PING, DB0=0, DB2=0, and DB1=66 keys after the worker health
job. The source and target recovery artifacts are operator custody, not Git
tracked files.

All image builds were linux/amd64 on `builder.home` and pushed to the
UFW-restricted anonymous registry at `builder.home:5555`; the remote registry
credentials remain value-free custody bridges. Quill readback reported these
immutable image manifests:

| Runtime       | Image manifest                                                            |
| ------------- | ------------------------------------------------------------------------- |
| API           | `sha256:4ff7e11e88ef5af7421b557633e4e2660f9f719b57dce9e77ab5f4f4b6409c16` |
| Worker/export | `sha256:9872990acd9ff623645c281d00e3b5beeb4fc0325816db1a30e8098a3020feab` |
| Sync          | `sha256:ec154963420ebec0f5922a2f1b8b839af4f30f9bfeb1c8e138e2d594d5ba83cf` |
| Styled text   | `sha256:3b91362a57385c6a637c124650d806978926008992effa381258b70e337304b6` |
| HTML-to-image | `sha256:103861c0ff46e6c29869a3f1f5597ea9f964b86323fd36e06b7ebcf0984ba158` |
| Private web   | `sha256:7e8d365607e39a9b68963078c065c2cffd3024bcce1251a639577687509b75c8` |

Direct-origin probes passed for API `/up`, the private web host, sync health, styled
Markdown-to-HTML, and an HTML-to-image PNG response. A real
`PostIndexHealthJob` was consumed by the worker. The private web root redirects
to `auth.camp.home`, API and sync health return 200, and a default avatar returns
`image/png` through `cdn.camp.home`. Browser sign-in, upload, and WebSocket
mutation remain explicit acceptance gaps.

## Networking and ingress

Quill application containers attach to the Docker `kamal` network. Groot's
MySQL and Redis are private host services reached at `192.168.10.33`; Redis
databases 0, 1, 2, and 3 remain assigned to Rails cache, Sidekiq, Rack Attack,
and sync coordination. Mantis publishes Elasticsearch only to the required
Quill source after its firewall is verified. Vyas object storage remains under
its private route contract.

✅ The target Redis allocation and AOF restore are deployed and restart-verified;
the sync runtime uses the existing Redis
accessory for Hocuspocus cross-replica document and awareness coordination. It
owns logical database 3 and the `campsite-sync` key/channel prefix; databases
0, 1, and 2 remain assigned to
Rails cache, Sidekiq, and Rack Attack respectively. Sync startup SHALL fail when
Redis coordination is unavailable, and `/up` SHALL return unavailable after a
Redis disconnect. The deployed runtime returns the Hocuspocus health response
on the private host alias; a two-client WebSocket mutation remains unproven.
Verification method: Test with two independently running sync processes and
Inspection of the rendered Kamal environment.

Historical search topology (superseded by the 2026-11-04 application release):
Elasticsearch listened on Mantis `192.168.10.34:9201`, required the application
credential, and is restricted to Quill (`192.168.10.32/32`) by explicit UFW
forward rules. Authenticated green health and zero unassigned shards are
verified; unauthenticated rejection and a non-Quill port rejection remain
acceptance checks. Its HTTP port is never routed through Cloudflare.

Caddy on Heimdall terminates private TLS for the `*.camp.home` family and
forwards application routes to Quill. `s3.camp.home` forwards object requests
to Vyas. Campsite has no active Cloudflare Tunnel ingress; public DNS records
may remain reserved, but the tunnel returns 404 and exposes no application
route.

✅ On 2026-11-04, API, worker/export, and styled-text were released at
`77a7bdc1874bbf40b0244ca83b0d3b446c100a4e`. Application search now uses the
existing PostgreSQL production database; no Elasticsearch service was started
or restored for this release. The external server's retirement was outside
scope. See [release evidence](../reviews/postgresql-search-release-2026-11-04.md)
for image digests, backup checkpoint, live checks, and CI/acceptance gaps.

The subsequent [security follow-up](../reviews/security-ci-follow-up-2026-11-04.md)
updated API and both worker roles to
`039d0fe39642f892d73ce0203f12def4bb1c3448`; styled-text remained at the cutover
revision. The follow-up verifies the patched runtime gems and authenticated
two-client note edits, reload persistence, search and test-resource cleanup.

## Outbound mail (✅ deployed)

Mail is delivered by the homelab Stalwart service on `vyas` (192.168.10.9), not
by Postmark. Its runbook lives in the `homelab` repository at
`runbooks/stalwart-on-vyas.md`; this repository owns only the client side.

| Setting               | Value                             |
| --------------------- | --------------------------------- |
| `SMTP_ADDRESS`        | `smtp.home`                       |
| `SMTP_PORT`           | `25`                              |
| `SMTP_DOMAIN`         | `agents.home`                     |
| `SMTP_AUTHENTICATION` | `none`                            |
| `SMTP_STARTTLS`       | `false`                           |
| `SMTP_OPEN_TIMEOUT`   | `15`                              |
| `SMTP_READ_TIMEOUT`   | `25`                              |
| `MAILER_FROM`         | `Campsite <campsite@agents.home>` |

The endpoint is unauthenticated and plaintext, and is reachable only inside the
homelab. `config/environments/production.rb` therefore omits `user_name`,
`password`, and `authentication` from `smtp_settings` when
`SMTP_AUTHENTICATION` is `none`. With every variable unset the defaults are
unchanged: Postmark on 587 with plain authentication and STARTTLS.

Stalwart runs with `MtaStageRcpt.allowRelaying` disabled, so it accepts
`@agents.home` recipients only and returns `550` for anything else. Signup
confirmations therefore reach only `@agents.home` addresses; any other address
fails in the background instead of reaching the user.

Devise no longer delivers inline. `User#send_devise_notification` queues through
Sidekiq, so a rejected recipient, a slow relay, or an unavailable one can no
longer 500 the signup request — `raise_delivery_errors` stays `true`, but it now
fails a job rather than a controller action. Mail failures surface in the worker
log and in Sidekiq retries, not in the browser.

`ActionMailer::MailDeliveryJob.enqueue_after_transaction_commit` is `true`
(`config/initializers/mail_delivery_job.rb`). `send_devise_notification` runs
inside the record's transaction and Rails 8.1 defaults this to `false`, so
without it Sidekiq can dequeue the job before the user row is visible and fail
to find it. The setting is per-job, so only mail delivery is affected.

The timeouts above exist because Stalwart's spam scan once held the SMTP DATA
phase for 12s, past Action Mailer's 5s default `read_timeout`. Inbound spam
filtering is now disabled on the server (see the runbook), so delivery settles
in well under a second; the headroom is retained deliberately.

Both `config/deploy.campsite-api.yml` and `config/deploy.campsite-worker.yml`
carry these variables; the worker sends the asynchronous mail and must stay in
step with the API. No SMTP secret is required, so `.kamal/campsite-secrets`
is unchanged.

As built, the live API and worker use the exact release tags and manifests in
the release evidence above. The running API resolves SMTP to `smtp.home:25`
with `open_timeout: 15`, `read_timeout: 25`, and no credential keys; a bounded
TCP probe from Quill succeeded. End-to-end authenticated mail delivery and
inbox receipt remain unproven in this cutover because the public/auth route is
not yet switched.

⚠️ **Kamal 2.12 app deploys must remain host-scoped.** Accessory commands use
`host: prakash@192.168.10.34`; application deploys target Quill
`192.168.10.32`. Keep the builder registry address routable from both ends;
unscoped deploys that resolve an accessory host as a registry-forward target are
not acceptance evidence.

## Durable storage and backups

PostgreSQL data lives on the Patroni hosts' persistent volumes; WAL and
pgBackRest backups are stored on Vyas. Redis and the retained MySQL rollback
source use Groot's persistent volume. Object data stays on Vyas authoritative
storage, and Elasticsearch uses a Mantis volume. The stopped Odin volumes are
historical rollback custody for the earlier homelab migration.

### 2026-10-30 MySQL to PostgreSQL cutover

The final paused-writer source dump is
`vyas:/volume1/shared/backups/campsite/mysql/camp-home-mysql-final-20261030T143446Z.sql.gz`
(SHA-256 `2390aafb18e718521e1c619307bb4f49f966f5892d43511d7c72b52573e8140d`).
It passed gzip integrity and disposable MySQL restore checks. The guarded
copy then loaded 100 tables into `campsite_production` on Patroni; the parity
check passed for 100 tables and 97 sequences before the API and workers were
restarted. The live MySQL source and data directory are removed. The final archive remains
for recovery evidence; rolling back to MySQL would require data reconciliation,
not only a Kamal revision change.

The post-cutover pgBackRest full backup is `20261030-150749F` in
`vyas:/volume1/shared/backups/campsite/pgbackrest`. `pgbackrest check` passed
with a new WAL segment archived, and `pgbackrest info` reported repository
status `ok`. The backup was restored into an isolated directory on Groot and
booted without network access. Recovery fetched the archived WAL, reached a
consistent read-only state, and returned 48 users from the restored database.
The disposable container and data directory were removed afterward. On 2026-10-30 both
Patroni hosts had the pgBackRest full and differential systemd timers enabled;
the next differential was scheduled for 2026-10-31 01:30 local time.

### Cutover evidence boundary

The migration SHALL be fail-closed until the source is reachable and its exact
container/volume is identified. Before any source mutation, record the MySQL
server version, schema version, database size, and critical row counts; take a
consistent logical dump and checksum it. Restore that dump into a disposable
MySQL target and compare schema and counts before provisioning the final Groot
volume. The final window pauses Rails and all Sidekiq/export writers, repeats a
consistent dump/restore, runs migrations from the exact API image, and compares
critical counts plus authenticated application reads. The untouched Odin
volume remains available for rollback.

Redis migration follows the same writer pause: preserve AOF and inspect logical
databases 0 (Rails cache), 1 (Sidekiq), 2 (Rack Attack), and 3 (sync). The
source AOF was rewritten and restored into a disposable Redis and the fresh
Groot target; the final target reports PING, DB0=0, DB2=0, and DB1=66 keys after
the worker acceptance job. A real `PostIndexHealthJob` was enqueued through the
API and consumed by the Quill worker. Search is rebuilt, never copied: the
zero-replica template is applied on Mantis, authenticated health is green with
no unassigned shards, and Post/Note/Call parity is 768/768, 68/68, and 0/0.
`/mnt/starkdrive-shared` is a soft NFS mount and is backup-only; it must not hold
live database files.

⚠️ The following cadence and restore methods are the backup design, not a
deployed recurring service. No Campsite backup timer was present on Groot at
the 2026-09-23 inspection. A backup's presence is not evidence of future runs.

The 2026-09-23 one-time `camp.home` MySQL backup is
`vyas:/volume1/shared/backups/campsite/mysql/camp-home-mysql-20260923T172625Z.sql.gz`.
The same archive is retained separately at
`ramonda:/srv/backups/applications/campsite/mysql/camp-home-mysql-20260923T172625Z.sql.gz`.
Both copies have SHA-256
`8c8bb87bc3b9e23bb768e3b797e36031dc6a90e51e673aa124b1fff4652961d3`.
The Vyas copy restored into an isolated MySQL 8.4 container on Ramonda with
104 tables, schema version `20260828134500`, and matching core row counts.

Garage's native metadata snapshot was taken before the separate-host archive
`ramonda:/srv/backups/applications/campsite/garage/garage-full-20260923T173040Z.tar.gz`.
It contains Garage object blocks, metadata snapshots, node identity/layout,
and configuration for the whole Garage instance, including the `campsite-media`
and `campsite-exports` buckets. Its SHA-256 is
`9aacc99eb58bf227acb681f3f0983fbeeb806ddb7a4da281b058a6d39e6e7a08`.
The archive passed gzip integrity checking and full extraction into a disposable
directory on Ramonda. The Ramonda database and Garage archives have the
filesystem immutable flag set to guard against accidental deletion. ⚠️ Isolated
Garage boot and object GET restore are not yet proven. Keep both archives
without pruning while recurring backup and restore checks are established.
Garage's live Vyas volume and its local metadata
snapshots alone are not separate-host backups.

After these copies and the MySQL restore check, the empty legacy tables
`follows`, `post_comments`, `post_files`, and `post_reactions` were dropped from
`camp.home` on 2026-09-23. The three `project_beads_*` tables were retained:
each had one live row despite being absent from the checked-in schema.

The intended recurring backup namespace is a dedicated, access-controlled
`vyas:/volume1/shared/backups/campsite/` directory, with a separate-host copy
on Ramonda:

| Data                     | Backup form                                      | Initial cadence | Restore evidence                                 |
| ------------------------ | ------------------------------------------------ | --------------- | ------------------------------------------------ |
| MySQL                    | consistent compressed logical dump plus checksum | daily           | restore into disposable MySQL and compare counts |
| Object store             | versioned mirror plus manifest/checksum          | daily           | fetch sampled old/current objects                |
| Elasticsearch            | repository snapshot, not a copied live volume    | daily           | restore disposable index and compare documents   |
| Redis/Sidekiq            | AOF copy after safe persistence operation        | daily           | start disposable Redis and inspect queues        |
| Kamal/Caddy declarations | Git-tracked configuration                        | each change     | render/validate configuration                    |

Runtime and backup credentials are separate. Backup writes are append-oriented;
the runtime credential cannot delete backup history. A backup is not accepted
until its restore rehearsal passes. XO VM backups complement but do not replace
these application-level backups. The Synology VMM guest is outside XO coverage.

Initial objectives are RPO 24 hours, RTO 8 hours, a four-hour cutover window,
and a seven-day rollback window. Those are planning baselines for the stated
one-to-two-user load.

## Secrets

Kamal injects secret names from the tracked, value-free
`.kamal/campsite-secrets` environment bridge; no secret value belongs in that
file, a deploy YAML file, image layer, Git history, or command output. The
dedicated `secrets_path` keeps homelab configs isolated from the legacy
Doppler-backed `.kamal/secrets-common` file while preserving that production
custody unchanged. The bridge references values loaded from the ignored
deployment profile `mise.deploy.toml`. `mise.local.toml` has higher precedence
than the deploy profile, so deployment commands must use
`script/campsite-deploy` to make the deployment profile authoritative even
when a local override exists.

Before rendering, building, or deploying any Campsite config, run:

```bash
mise -E deploy exec -- script/campsite-deploy script/check-campsite-kamal-secrets
```

The preflight derives required names from every `deploy.campsite-*.yml`, checks
that each config selects the dedicated bridge and that it contains
environment-only references, reports presence by name only, and exits nonzero
when anything is missing. For API and worker deploys it also checks that
`ELASTICSEARCH_URL` matches the authenticated endpoint declared by the API's
Elasticsearch accessory. The Rails credentials key,
database URLs, object-store keys, Elasticsearch credential, provider
credentials, and observability tokens are required inputs. The current deploy
profile contains all required runtime names, including
`KAMAL_REGISTRY_USER_NAME` and `KAMAL_REGISTRY_PASSWORD`; the preflight reports
presence by name only. Registry credentials are not required by the current
anonymous, UFW-restricted design. A successful config render does not override
a failing secret preflight if custody is later removed.

A build does not need runtime or accessory credentials. Before an isolated
build, restrict the preflight to that config's BuildKit secrets:

```bash
mise -E deploy exec -- script/campsite-deploy script/check-campsite-kamal-secrets --scope=build config/deploy.campsite-web.yml
```

Do not use build scope as deploy evidence; the default deploy scope remains the
required gate before any application or accessory mutation.

Run all Kamal commands through the deployment profile wrapper. For example:

```bash
mise -E deploy exec -- script/campsite-deploy kamal deploy -c config/deploy.campsite-api.yml
```

Image builds never upload source maps or perform another observability-provider
mutation. BuildKit receives only credentials needed to read private packages.
Sentry/Glitchtip source-map publication is a separate release action with its
own explicit authorization, credentials, receipt, and rollback/revocation
record; a successful image build is not evidence that publication occurred.

Credentials are grouped by custody:

- runtime: least privilege for normal application reads/writes;
- migration: temporary source read and destination write access;
- backup: destination append/write and source read access;
- operator: provisioning and restore authority, never injected into apps.

Migration credentials are revoked after the rollback window. Provider secrets
remain unchanged unless their callback or hostname contract requires rotation.

## Observability and operations

❌ Target-host Beszel coverage is not proven. Add guest/container visibility and
alerts for Quill/Groot/Mantis memory/disk, container restarts, Elasticsearch
heap/cluster state, MySQL health and free space, Redis persistence/queue
latency, object-store disk, private ingress failures, and backup age.

Synthetic checks must cover the private web page, authenticated API path,
WebSocket connection, styled-text request, HTML-to-image PNG response, an
object upload/download, a queued job, and search indexing/querying. A bare
health endpoint does not prove those user paths.

## Failure and rollback behavior

| Failure                    | Expected behavior                                                                                    | Recovery                                                                        |
| -------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Quill/Groot/Mantis restart | host/service restart can interrupt the stack; an unclean Quill stop can leave containers unstartable | verify durable stores, then `script/campsite-recover` (see below)               |
| Elasticsearch VM loss      | writes continue only where app semantics allow; search is reported unavailable                       | restore/rebuild guest and fresh index, then reconcile/reindex                   |
| Heimdall/Caddy loss        | private application names are unavailable                                                            | restore Caddy and verify the local routes                                       |
| starkdrive/NFS loss        | live service continues; backups fail closed and alert                                                | restore NAS path, then run and verify missed backup                             |
| Internet loss              | local stack stays up; external integrations fail/retry                                               | reconcile provider jobs after connectivity returns                              |
| Power loss                 | 🟡 observed 2026-10-28: Quill's containers did not restart (see below)                               | ordered datastore health checks, then `script/campsite-recover`                 |
| Bad application release    | previous immutable image remains selectable                                                          | `kamal rollback` per runtime                                                    |
| Bad data migration         | staging stack remains isolated                                                                       | stop new writers, restore destination, return DNS/provider custody to old stack |

There is no evidence of UPS protection, so the declared availability is
single-site and power-loss exposed. The staging scheduler stays disabled until
its separate promotion gate, preventing duplicate scheduled outbound effects.

### Unclean Quill stops

On 2026-10-28 knowhere (Quill's XCP-ng host, an N150 mini PC) stopped
uncleanly three times: an unexplained reboot, a power pull, and a crash during
an image pull. Each time Docker came back with every container unstartable
(`RWLayer of container … is unexpectedly nil`), and the containerd image
store's snapshot and content metadata no longer matched its data, so pulls
failed too. A freshly reset containerd store was corrupted again by the next
crash.

Quill's Docker now uses the classic `overlay2` storage driver
(`"features": {"containerd-snapshotter": false}` in `/etc/docker/daemon.json`,
backup at `daemon.json.bak-20261029`). 🟡 It has not yet been through an
unclean stop. The broken stores are retained at
`/srv/campsite-runtime/{containerd,docker}.broken-2026102{8,9}` until they are
deliberately removed.

Quill's containers hold no state, so recovery is a redeploy of the versions
that last ran:

```bash
mise -E deploy exec -- script/campsite-recover --dry-run
mise -E deploy exec -- script/campsite-recover
```

It reads each service's last started version from Kamal's audit log on Quill
(`~/.kamal/<service>-audit.log`, outside Docker), skips services already running
at that version, deploys the API first because that deploy recreates
`kamal-proxy`, and boots `etcd-c` from the pg-ha-cluster worktree (`PG_WORKTREE`)
with `--hosts`. `SERVICE=VERSION` arguments override the audit log.

❌ knowhere has no UPS or graceful-shutdown path, and its cooling is unresolved
(`campsite-5yu`). Shut the host down from XCP-ng (`xe host-shutdown`) before
any physical work.

## Promotion gates

Remaining promotion gates are the authenticated browser flow, two-client sync
mutation, and Vyas object upload/download. Exact
amd64 image builds, Rails migrations, search reindex, source inventory,
consistent dump/disposable restore, Groot/Mantis persistence, SMTP reachability,
and direct-origin service probes are complete as recorded above. Each host,
DNS, and provider mutation remains a separately approved action.
