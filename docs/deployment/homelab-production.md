# Campsite homelab production platform

Status: declared design; no production cutover is implied by this document.

This is the target platform for the `camp.tokdio.com` migration. Kamal is the
deployment control plane for every Campsite application runtime and stateful
accessory. The split is by deploy configuration because Kamal deploys one
application image per configuration; it is not a return to hand-managed SSH
deployments.

## Service placement

| Component                  | Kamal unit  | Host                 | Ceiling           | Persistence                 | Health signal                   |
| -------------------------- | ----------- | -------------------- | ----------------- | --------------------------- | ------------------------------- |
| Next.js web                | application | Odin `192.168.10.7`  | 512 MiB           | none                        | HTTP `/up`                      |
| Rails API/auth             | application | Odin                 | 768 MiB           | none                        | HTTP `/up`                      |
| Sidekiq                    | application | Odin                 | 512 MiB           | none                        | process plus queue latency      |
| Sync server                | application | Odin                 | 256 MiB           | none                        | HTTP `/up` and WebSocket probe  |
| Styled-text server         | application | Odin                 | 256 MiB           | none                        | HTTP `/up`                      |
| HTML-to-image              | application | Odin                 | 512 MiB           | none                        | HTTP `/up` and PNG render probe |
| MySQL 8                    | accessory   | Odin                 | 1 GiB             | local named volume          | `mysqladmin ping`               |
| Redis                      | accessory   | Odin                 | 256 MiB           | local named volume with AOF | `redis-cli ping`                |
| S3-compatible object store | accessory   | Odin                 | 512 MiB           | local named volume          | readiness endpoint              |
| Elasticsearch 8.8          | accessory   | Shuri `192.168.20.14` | 2 GiB, 1 GiB heap | local named volume          | cluster health                  |

Odin is the application and primary-data host. Shuri is the search host because
Elasticsearch's measured footprint fits its 2 GiB cap while Asgard has only
about 1.64 GB of unallocated host memory with its normal VM set running. This
is a small, single-node topology for one or two users, not a high-availability
cluster.

The listed ceilings total 4.6 GiB on Odin before Kamal proxy and system
overhead. Provisioning must stop if imported durable data does not fit with at
least 20 GiB free on Odin's root disk. Current provider data sizes are
unavailable until Fly/provider authentication is restored.

## Kamal layout

The production declaration will be split into these destination-specific files
while sharing host, registry, secret, and network conventions:

| File                                | Responsibility                                                    |
| ----------------------------------- | ----------------------------------------------------------------- |
| `deploy.campsite-web.yml`           | Next.js web                                                       |
| `deploy.campsite-api.yml`           | Rails web and the authenticated Shuri Elasticsearch declaration   |
| `deploy.campsite-worker.yml`        | Sidekiq only; explicit writer-custody activation                   |
| `deploy.campsite-sync.yml`          | Sync server                                                       |
| `deploy.campsite-styled-text.yml`   | Styled-text server                                                |
| `deploy.campsite-html-to-image.yml` | HTML-to-image                                                     |
| `deploy.campsite-shadow.yml`        | Isolated HTML-to-image plus loopback-only shadow Elasticsearch    |

The Rails web and Sidekiq services deliberately do not share a Kamal config.
Deploying `deploy.campsite-api.yml` therefore cannot start a queue consumer.
`deploy.campsite-worker.yml` reuses the exact Rails image and remains disabled
until the writer-custody gate explicitly authorizes queue consumption. Its
scheduler is also disabled by default and requires a separate promotion step.

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
Build placement follows the destination architecture. Custom images deployed to
the arm64 Shuri host are built locally on the operator's arm64 Mac. Custom images
deployed to the amd64 Debian host are built remotely on Odin. Campsite does not
use Forge as a builder. The current topology deploys every custom Campsite image
to Odin; Shuri only pulls Elasticsearch's upstream multi-platform image, so no
custom arm64 build is currently required. Images use a private registry; the
current Odin-local registry is acceptable for shadow work but is not a durable
production registry until its storage and backup are declared.

Runtime base images and Elasticsearch are also pinned to immutable manifest
digests. Node-based images use the repository's declared Node 24.19.0 runtime;
all application processes run as unprivileged users. Updating a base image or
Elasticsearch therefore requires an explicit digest refresh and rebuild rather
than silently following a mutable registry tag.

Deploys use Kamal commands from the operator workstation. SSH is Kamal's
transport, not an independent deployment procedure. Direct host commands are
reserved for provisioning prerequisites and break-glass recovery and require a
separate mutation approval.

## Networking and ingress

Application containers and Odin accessories attach to the Docker `kamal`
network. MySQL, Redis, and the object-store administration endpoint publish no
public ports. Application containers address them by stable accessory service
name.

Elasticsearch listens on Shuri's LAN address only, requires an application
credential, and is restricted to Odin at the host firewall. Its HTTP port is
never routed through Cloudflare. The current loopback-only shadow binding must
remain until that authenticated LAN path and firewall rule are provisioned
together.

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

## Durable storage and backups

Live MySQL, Redis, and object data stay on Odin-local Docker volumes so a NAS
or LAN interruption does not corrupt an active database. Elasticsearch stays
on Shuri-local Docker storage. `/mnt/starkdrive-shared` is a soft NFS mount and
is backup-only; it must not hold live database files.

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
these application-level backups, and Shuri is outside XO coverage.

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
`mise exec --` from the ignored, age-encrypted `mise.local.toml` or from the
operator environment.

Before rendering, building, or deploying any Campsite config, run:

```bash
mise exec -- script/check-campsite-kamal-secrets
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
mise exec -- script/check-campsite-kamal-secrets --scope=build config/deploy.campsite-web.yml
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

Beszel already observes Odin, Shuri, and Heimdall. Add Campsite container
visibility and alerts for host memory/disk, container restarts, MySQL health and
free space, Redis persistence/queue latency, Elasticsearch heap/cluster state,
object-store disk, Cloudflare origin failures, and backup age.

Synthetic checks must cover the public web page, authenticated API path,
WebSocket connection, styled-text request, HTML-to-image PNG response, an
object upload/download, a queued job, and search indexing/querying. A bare
health endpoint does not prove those user paths.

## Failure and rollback behavior

| Failure                   | Expected behavior                                                              | Recovery                                                                        |
| ------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| Odin VM/container restart | auto-start VM; Kamal-managed containers restart                                | verify durable stores before apps/workers                                       |
| Shuri/Elasticsearch loss  | writes continue only where app semantics allow; search is reported unavailable | restore/start ES, then reconcile/reindex                                        |
| Heimdall/tunnel loss      | public site unavailable; private services remain closed                        | restore tunnel; no direct public port fallback                                  |
| starkdrive/NFS loss       | live service continues; backups fail closed and alert                          | restore NAS path, then run and verify missed backup                             |
| Internet loss             | local stack stays up; external integrations fail/retry                         | reconcile provider jobs after connectivity returns                              |
| Power loss                | Odin VM auto-starts; Shuri behavior must be verified separately                | ordered datastore health checks before workers                                  |
| Bad application release   | previous immutable image remains selectable                                    | `kamal rollback` per runtime                                                    |
| Bad data migration        | new stack remains isolated                                                     | stop new writers, restore destination, return DNS/provider custody to old stack |

There is no evidence of UPS protection, so the declared availability is
single-site and power-loss exposed. Scheduled workers stay disabled on the
shadow stack until the explicit writer-custody step, preventing duplicate
outbound effects.

## Promotion gates

Provisioning may begin only after provider data sizes are measured or bounded,
backup paths and credentials are created, Elasticsearch's authenticated private
path is ready, and the destination-matched builder can publish immutable images.
Cutover additionally requires restored backups, a full shadow-stack acceptance
run, one rehearsed rollback, and an immutable provider/DNS change set. Each host,
Cloudflare, DNS, and provider mutation remains a separately approved action.
