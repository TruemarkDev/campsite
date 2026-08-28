# Campsite homelab staging platform

Status: partially deployed. The staging application services are live on Odin,
and the dedicated Elasticsearch VM is live on Vyas; sections below retain
explicit gap markers for unverified or unbuilt parts of the wider platform.

This is the target platform for the `camp.tokdio.com` migration. Kamal is the
deployment control plane for every Campsite application runtime and stateful
accessory. The split is by deploy configuration because Kamal deploys one
application image per configuration; it is not a return to hand-managed SSH
deployments.

## Service placement

| Component                  | Kamal unit  | Host                     | Ceiling           | Persistence                 | Health signal                   |
| -------------------------- | ----------- | ------------------------ | ----------------- | --------------------------- | ------------------------------- |
| Next.js web                | application | Odin `192.168.10.7`      | 512 MiB           | none                        | HTTP `/up`                      |
| Rails API/auth             | application | Odin                     | 768 MiB           | none                        | HTTP `/up`                      |
| Sidekiq                    | application | Odin                     | 512 MiB           | none                        | process plus queue latency      |
| Sync server                | application | Odin                     | 256 MiB           | none                        | HTTP `/up` and WebSocket probe  |
| Styled-text server         | application | Odin                     | 256 MiB           | none                        | HTTP `/up`                      |
| HTML-to-image              | application | Odin                     | 512 MiB           | none                        | HTTP `/up` and PNG render probe |
| MySQL 8                    | accessory   | Odin                     | 1 GiB             | local named volume          | `mysqladmin ping`               |
| Redis                      | accessory   | Odin                     | 256 MiB           | local named volume with AOF | `redis-cli ping`                |
| S3-compatible object store | accessory   | Odin                     | 512 MiB           | local named volume          | readiness endpoint              |
| Elasticsearch 9.5          | accessory   | Vyas VMM `192.168.10.26` | 2 GiB, 1 GiB heap | guest-local named volume    | authenticated cluster health    |

The 2 GiB / 1 GiB-heap limit is verified against Elasticsearch 9.5 after the
production reindex: the container used 1.39 GiB, the 4 GiB guest retained about
2 GiB available, and its 60 GiB disk retained 53 GiB free. Vyas retained about
3 GiB available with Builder, Friday, and Elasticsearch running, so further
fixed-memory VMM guests require a fresh capacity check.

Odin is the application and primary-data host. Elasticsearch runs in a dedicated
Debian 13 VMM guest on Vyas because Odin and the XCP-ng pool lack safe memory
headroom. This is a small, single-node topology for one or two users, not a
high-availability cluster.

The listed ceilings total 4.6 GiB on Odin before Kamal proxy and system
overhead. Provisioning must stop if imported durable data does not fit with at
least 20 GiB free on Odin's root disk. Current provider data sizes are
unavailable until Fly/provider authentication is restored.

## Kamal layout

The staging declaration is split into these destination-specific files
while sharing host, registry, secret, and network conventions:

| File                                | Responsibility                                                     |
| ----------------------------------- | ------------------------------------------------------------------ |
| `deploy.campsite-web.yml`           | Next.js web                                                        |
| `deploy.campsite-api.yml`           | Rails web and the authenticated Vyas VMM Elasticsearch declaration |
| `deploy.campsite-worker.yml`        | Sidekiq only; explicit writer-custody activation                   |
| `deploy.campsite-sync.yml`          | Sync server                                                        |
| `deploy.campsite-styled-text.yml`   | Styled-text server                                                 |
| `deploy.campsite-html-to-image.yml` | HTML-to-image                                                      |

The Rails web and Sidekiq services deliberately do not share a Kamal config.
Deploying `deploy.campsite-api.yml` therefore cannot start a queue consumer.
`deploy.campsite-worker.yml` reuses the Rails image. Writer custody has moved to
the homelab worker, while its scheduler remains disabled by default and requires
a separate promotion step.

### Canonical staging identities

Every Kamal application and accessory declaration uses `staging` as its
environment identity. The two web builds remain intentionally distinct because
their public URLs are compiled into the image:

| Runtime             | Kamal service                    |
| ------------------- | -------------------------------- |
| Rails API/auth      | `campsite-api-staging`           |
| Sidekiq             | `campsite-worker-staging`        |
| Public Next.js web  | `campsite-web-public-staging`    |
| Private Next.js web | `campsite-web-home-staging`      |
| Sync                | `campsite-sync-staging`          |
| Styled text         | `campsite-styled-text-staging`   |
| HTML-to-image       | `campsite-html-to-image-staging` |

Public `camp*.tokdio.com` and private HTTPS `*.camp.home` hostnames are stable
interfaces, not environment labels, and remain unchanged. The existing
`campsite-api-tokdio_*` named volumes are also retained intentionally so a
service rename cannot create empty MySQL, Redis, object, or Elasticsearch
stores.

🟡 The checked-in service identities are renamed, but some running containers
still use previous names pending the coordinated Kamal cutover. The active
`campsite-shadow-html-to-image` container is a legacy duplicate service. The
former Shuri Elasticsearch state is outside the live topology; retirement of
either orphan still requires separate operator approval.

### Voice-note runtime gate

Voice-note processing runs inside the Sidekiq container, so installing speech
tools only on the Odin host does not satisfy the runtime contract. The immutable
worker image SHALL contain `whisper-cli`, its separately supplied GGML model,
and `edge-tts` (Verification: Inspection); see `api/README.md` for environment
names and smoke tests.
❌ The current worker image contains `ffmpeg` but does not contain the other
speech dependencies, and the smoke tests have not been demonstrated on Odin.
Worker promotion with voice notes enabled is therefore blocked until a subsequent
image/provisioning change supplies and verifies them. The check SHALL run before
writer custody is activated and SHALL be repeated after a speech-tool or base-image
upgrade (Verification: Demonstration).

All application images are immutable and tagged with the exact Git revision.
Custom amd64 application images are built on `builder.home` and deployed to
Odin. The Elasticsearch guest pulls Elastic's pinned upstream amd64 image
directly, so it is not an application builder or private-registry target. Images
use a private registry; the current Odin-local registry is acceptable for
staging work but is not a durable production registry until its storage and
backup are declared.

Runtime base images and Elasticsearch are also pinned to immutable manifest
digests. Node-based images use the repository's declared Node 24.19.0 runtime;
all application processes run as unprivileged users. Updating a base image or
Elasticsearch therefore requires an explicit digest refresh and rebuild rather
than silently following a mutable registry tag.

### Elasticsearch 9.5 migration (✅ deployed 2026-08-28)

The declared image moved from 8.8.0 to 9.5.0. Elastic does not support a direct
rolling upgrade from 8.8 to 9.x — the documented path is 8.8 → 8.19 (the last
8.x minor) → 9.x, and indices created by 7.x are unreadable in 9.x.

Campsite's Elasticsearch holds only derived search indices, every one of which
is rebuildable from MySQL, so the recommended path skips the ladder entirely:

1. Stop the accessory and the workers that write to it.
2. Create a fresh `campsite-api-tokdio_elasticsearch-data` volume — do not carry
   the inaccessible Shuri 8.8 data directory across.
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

The live migration completed on the dedicated VMM guest. The pinned digest is
`sha256:8818ab9af72d7482e38a9d6f0454d5ee667564a25bbdc42360c0f9b8f8f72fc5`;
authenticated health from Odin was green with one node and no unassigned
shards. A Kamal accessory restart preserved the cluster UUID. With Sidekiq
paused, `searchkick:reindex:all` completed and counts matched exactly: Post
760/760, Note 67/67, and Call 0/0. API and worker then both proved authenticated
connectivity before Sidekiq resumed. The declared
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

## Networking and ingress

Application containers and Odin accessories attach to the Docker `kamal`
network. MySQL, Redis, and the object-store administration endpoint publish no
public ports. Application containers address them by stable accessory service
name.

🟡 Declared locally; not yet deployed. The sync runtime uses the existing Redis
accessory for Hocuspocus cross-replica document and awareness coordination. It
owns logical database 3 and the `campsite-sync` key/channel prefix; databases
0, 1, and 2 remain assigned to
Rails cache, Sidekiq, and Rack Attack respectively. Sync startup SHALL fail when
Redis coordination is unavailable, and `/up` SHALL return unavailable after a
Redis disconnect. Verification method: Test with two independently running sync
processes and Inspection of the rendered Kamal environment.

Elasticsearch listens on `192.168.10.26:9201`, requires the application
credential, and is restricted to Odin (`192.168.10.7/32`) by the guest's
Docker-aware UFW policy. An authenticated Odin request returns green, an
unauthenticated Odin request returns 401, and a non-Odin port probe is rejected.
Its HTTP port is never routed through Cloudflare.

Heimdall's named Cloudflare Tunnel is the only public ingress. It forwards the
tokdio host family to Kamal proxy on Odin over private HTTP:

- `camp.tokdio.com` to the web runtime
- `camp-api.tokdio.com` and `camp-auth.tokdio.com` to Rails
- `camp-sync.tokdio.com` to the sync runtime with WebSocket support
- `camp-styled-text.tokdio.com` to styled text
- `camp-html-to-image.tokdio.com` to HTML-to-image

Cloudflare terminates public TLS. Kamal proxy routes by preserved Host header.
No old API, OAuth, webhook, POST, or WebSocket hostname is implemented as an
HTTP redirect during the rollback window.

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

As built, the live API runs `65aa744c68ddaf8209b410af0cb22c55b1dba0fd` and the
worker `b955395ae56b4b52032b60fa7959ce846f175a84`; both carry the same mail
settings, and both revisions include the deferred-delivery change. Verified in
the running API container: `smtp_settings` resolves to `smtp.home:25` with
`open_timeout: 15`, `read_timeout: 25` and no credential keys; the
`send_devise_notification` override is active; and the mail job's
after-commit flag is set. A production Action Mailer message from
`campsite@agents.home` was accepted by SMTP in 0.75s and ingested to the
`prakash@agents.home` inbox.

⚠️ **Kamal 2.12 app deploys must remain host-scoped.** Accessory commands accept
`host: prakash@192.168.10.26`, but an unscoped application deploy also treats
that user-qualified accessory host as a registry-forward target and fails with
`Socket::ResolutionError`. Deploy the API with `--hosts=192.168.10.7`; direct
`kamal accessory` commands continue to own Elasticsearch lifecycle operations.

## Durable storage and backups

Live MySQL, Redis, and object data stay on Odin-local Docker volumes.
Elasticsearch uses a guest-local Docker volume on the Vyas VMM datastore; it is
derived from MySQL and can be rebuilt when the VM or volume is lost.
`/mnt/starkdrive-shared` is a soft NFS mount and is backup-only; it must not hold
live database files.

Backup destinations are rooted under a dedicated, access-controlled
`starkdrive:/volume1/backups/campsite/` namespace:

| Data                          | Backup form                                      | Initial cadence | Restore evidence                                 |
| ----------------------------- | ------------------------------------------------ | --------------- | ------------------------------------------------ |
| MySQL                         | consistent compressed logical dump plus checksum | daily           | restore into disposable MySQL and compare counts |
| Object store                  | versioned mirror plus manifest/checksum          | daily           | fetch sampled old/current objects                |
| Elasticsearch                 | repository snapshot, not a copied live volume    | daily           | restore disposable index and compare documents   |
| Redis/Sidekiq                 | AOF copy after safe persistence operation        | daily           | start disposable Redis and inspect queues        |
| Kamal/Cloudflare declarations | Git-tracked configuration                        | each change     | render/validate configuration                    |

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
custody unchanged. The bridge references values loaded by
`mise -E deploy exec --` from the ignored, age-encrypted
`mise.deploy.toml` profile or from the operator environment.

Before rendering, building, or deploying any Campsite config, run:

```bash
mise -E deploy exec -- script/check-campsite-kamal-secrets
```

The preflight derives required names from every `deploy.campsite-*.yml`, checks
that each config selects the dedicated bridge and that it contains
environment-only references, reports presence by name only, and exits nonzero
when anything is missing. The Rails credentials key,
database URLs, object-store keys, Elasticsearch credential, provider
credentials, and observability tokens are required inputs. At the time this
platform was declared, only the private Tiptap registry token was present; a
successful config render does not override a failing secret preflight.

A build does not need runtime or accessory credentials. Before an isolated
build, restrict the preflight to that config's BuildKit secrets:

```bash
mise -E deploy exec -- script/check-campsite-kamal-secrets --scope=build config/deploy.campsite-web.yml
```

Do not use build scope as deploy evidence; the default deploy scope remains the
required gate before any application or accessory mutation.

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

Beszel already observes Odin, Shuri, and Heimdall. ❌ The new Elasticsearch VM
does not yet have a Beszel agent. Add guest/container visibility and alerts for
host memory/disk, container restarts, Elasticsearch heap/cluster state, MySQL
health and free space, Redis persistence/queue latency, object-store disk,
Cloudflare origin failures, and backup age.

Synthetic checks must cover the public web page, authenticated API path,
WebSocket connection, styled-text request, HTML-to-image PNG response, an
object upload/download, a queued job, and search indexing/querying. A bare
health endpoint does not prove those user paths.

## Failure and rollback behavior

| Failure                   | Expected behavior                                                                                        | Recovery                                                                        |
| ------------------------- | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Odin VM/container restart | auto-start VM; Kamal-managed containers restart                                                          | verify durable stores before apps/workers                                       |
| Elasticsearch VM loss     | writes continue only where app semantics allow; search is reported unavailable                           | restore/rebuild guest and fresh index, then reconcile/reindex                   |
| Heimdall/tunnel loss      | public site unavailable; private services remain closed                                                  | restore tunnel; no direct public port fallback                                  |
| starkdrive/NFS loss       | live service continues; backups fail closed and alert                                                    | restore NAS path, then run and verify missed backup                             |
| Internet loss             | local stack stays up; external integrations fail/retry                                                   | reconcile provider jobs after connectivity returns                              |
| Power loss                | Odin auto-starts; VMM autorun and container restart are configured, but a Vyas power-cycle is unverified | ordered datastore health checks before workers                                  |
| Bad application release   | previous immutable image remains selectable                                                              | `kamal rollback` per runtime                                                    |
| Bad data migration        | staging stack remains isolated                                                                           | stop new writers, restore destination, return DNS/provider custody to old stack |

There is no evidence of UPS protection, so the declared availability is
single-site and power-loss exposed. The staging scheduler stays disabled until
its separate promotion gate, preventing duplicate scheduled outbound effects.

## Promotion gates

Elasticsearch's authenticated private path is ready. Remaining promotion gates
are provider data-size bounds, created and tested backup paths/credentials, and
proof that the destination-matched builder can publish immutable images.
Cutover additionally requires restored backups, a full staging-stack acceptance
run, one rehearsed rollback, and an immutable provider/DNS change set. Each host,
Cloudflare, DNS, and provider mutation remains a separately approved action.
