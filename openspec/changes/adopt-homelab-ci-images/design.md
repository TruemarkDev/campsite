# Proposed design

❌ Unbuilt. Source observations below were inspected on 2026-09-24; they do not
establish deployed runner state or registry throughput.

## Existing state and ownership

| Evidence | Observation |
| --- | --- |
| Campsite `.forgejo/workflows/api-tests.yml` | `campsite-ruby40`; CA/bootstrap, apt, Node and pnpm installation precede checkout; bundler-audit, Brakeman, RuboCop and Rails tests share one job |
| Campsite `mise.toml`, `api/mise.toml`, version files and Dockerfiles | Ruby 4.0.6 and Node 24.19.0; root engine range excludes Node 26 |
| Campsite `packages/eslint-config-campsite/flat-base.mjs` | Type information enabled; recommended type-checked rules not enabled as a set |
| Homelab `docker/forgejo-runner/runner-config.yml` | Existing label maps to stock Ruby image; capacity one; Actions cache disabled |
| Homelab `kubernetes/clusters/homelab/workloads/forgejo-runner/` | Separate canary label; ephemeral DinD data; cache disabled; scale zero-to-one |
| Homelab `stacks/vyas-services/docker-compose.yml` | Forgejo and Docker Hub cache bind Vyas volume storage |
| Homelab `runbooks/oci-image-cache.md` | `git.home` writable registry; `docker-cache.home` Docker Hub pull-through cache; builder has a scoped Kamal role |

Prior endpoint checks in this conversation returned verified HTTPS responses:
registry authentication challenge at `git.home/v2/`, and 200 at
`docker-cache.home/v2/`. Authenticated image push/pull and throughput remain open.
K3s canary acceptance is not evidence that Campsite already runs on K3s.

The homelab root currently reports a bare repository. Implementation first
establishes a dedicated worktree from the operator's integration branch and
reads its current instructions. No default-main assumption. Image definitions
belong under `docker/ci-images/`; Kubernetes changes remain with the existing
chart; host provisioning remains Ansible-owned. No second deployment owner.
This cross-repository proposal remains the single requirements source; homelab
documentation links it rather than copying it.

## Image profiles

Proposed published names (not yet existing image references):

| Image | Contents and purpose |
| --- | --- |
| `git.home/tokdio/ci-node26` | Exact Node and pnpm; Git, CA certificates, reviewdog and Gitleaks; JS analysis/tests |
| `git.home/tokdio/ci-ruby40-node26` | Exact Ruby, Bundler, Node and pnpm; compiler/pkg-config/MySQL development libraries and API-required ffmpeg; Git, CA, reviewdog and Gitleaks |
| `git.home/tokdio/ci-security` | Exact Semgrep, Trivy, Gitleaks, reviewdog and supported runtime for JavaScript actions; security scans |

Begin with the Ruby/Node profile and Node profile. Add the security profile when
its workflow is ready. Share build recipes/layers where compatible without
forcing a large Ruby/compiler image onto frontend jobs. Keep browser binaries
in a separate test image if Playwright/Puppeteer acceptance needs them.

The image is the job environment, not the Forgejo runner manager. No Docker
daemon or host Docker socket is required inside analysis images. Build native
linux/amd64 first; add arm64 only when a named consumer needs it. A dedicated
authorized image build job owns publication; do not repurpose the Kamal-only
builder implicitly. Builder selection and capacity are rollout prerequisites.

Image manifests pin official bases by digest and tools by exact version and
verified checksum/signature where available. Follow each tool's official
installation/update mechanism and inspect its current documentation before
automation. Record origins and updates in the image manifest/runbook and the
operator tool inventory when a local tool is installed. No floating `latest`
reference or network install pipe in consuming jobs.

Project lockfiles continue to own ESLint, TypeScript, RuboCop, Brakeman and
other application dependencies. Cached installations remain validated by
frozen pnpm/Bundler resolution. The images contain no project secrets, registry
credentials or review tokens. Public homelab CA trust includes Node's trust
configuration and has a tested rotation path. The pulling daemon must trust
the registry before it can fetch an image; trust inside that image is insufficient.

## Runtime migration

Official release references:

- https://www.ruby-lang.org/en/downloads/ — Ruby 4.0.7 at planning time.
- https://nodejs.org/en/download/current — Node 26.10.0 Current at planning time.

Recheck releases and official image availability when implementation begins.
Use released stable versions, excluding preview/nightly builds. Select exact
versions and compatible distro images; resolve matching digests rather than
reusing Node 24 or Ruby 4.0.6 digests. Keep pnpm at its project pin unless a
verified compatibility need requires a deliberate update.

Align `mise.toml`, `api/mise.toml`, `.nvmrc`, `api/.ruby-version`, package engines,
all active application Dockerfiles (including html-to-image), affected lockfile
runtime metadata, workflow labels, `MAINTENANCE.md`, `AGENTS.md` and stale
toolchain comments. Add a parity check based on canonical project pins and
image metadata, avoiding a second version database.

Compatibility checks cover native Ruby gems, Rails assets, Next.js production
builds, sync/styled-text services, Puppeteer and workspace typechecks/tests.
Compare existing failing checks on the baseline before attributing them to
the upgrade. Source alignment is not deployment acceptance. Application release
and any production runtime change use the separate deployment procedure.

## Workflow and PR feedback

Proposed jobs: `quality-ruby`, `quality-js`, `security`, `test-api`, and
`test-js`. Split build/typecheck validation as project scripts require. Static
jobs avoid MySQL/Redis/Elasticsearch service startup. Keep API parallel workers
bounded by measured memory; splitting jobs does not itself increase concurrency.

Keep RuboCop/Brakeman and existing ESLint rules; add reviewed type-aware rules,
Semgrep and Gitleaks, dependency audits and Trivy image/config scanning.
Oxlint evaluation is optional follow-up, not a prerequisite. Use `campsite-jc3`
for explicit Brakeman ignore selection. Existing debt gets reviewed baselines;
new findings and scanner failures remain visible. Secret findings are redacted.

Scanners write machine-readable artifacts and preserve their exit status.
reviewdog's Gitea reporter is a candidate integration, not assumed reliable.
Pin it and test missing permission, renamed files, stale head, repeated run,
introduced finding and fixed finding on the actual Forgejo version. Reviewdog
does not control scanner success. Report publication failure explicitly.

A trusted publisher consumes bounded report data without executing PR code,
uses least-privilege credentials and verifies repository/PR/head SHA before
writing. Fork analysis runs without write credentials; use the supported
trusted follow-up mechanism only after checking installed Forgejo capabilities.
Unsafe privileged triggers checking out PR code are excluded. Pin publisher
code from the trusted base; escape report text and cap comment volume.
Required checks bind to the analyzed head and include all mandatory jobs.

## Cache and latency design

Use native Forgejo cache support after checking the installed runner's supported
configuration, reachability and authentication. Cache pnpm store and Bundler
downloads/installations by OS, architecture, runtime, image ABI and lockfile.
Trusted and untrusted writes use separate namespaces; PR jobs cannot poison
trusted release caches. No shared mutable node_modules across jobs.

Keep image delivery and dependency cache measurements separate. A local
registry saves upstream transfer but not decompression/unpacking. K3s
containerd pre-pulls do not populate the nested DinD store. Never mount one
writable Docker data directory into multiple daemons. Retained per-worker
stores need an explicit isolation/lifecycle design; do not quietly replace
ephemeral job isolation for speed. Persistent BuildKit cache applies to image
builds, not automatically to job-container startup.

First canary the current Campsite runner. Keep K3s migration independent until
its provider acceptance and capacity gates pass. Assess a warm runner and
SSD/NVMe placement only after observing startup latency and storage pressure.
Current one-job limits remain until live resource admission supports a change.
No registry migration or new registry product is needed for this proposal.

Benchmark the same source/test scope and worker allocation before and after.
Record queue delay, runner readiness, image transfer/unpack, checkout,
dependency restore/install, service readiness, analyzer/test execution and PR
publication. Collect repeated cold and warm runs with exact image/source
digests and cache state; report median/range and sample size. Select numerical
latency goals from that baseline with the operator; none is invented here.
Acceptance requires demonstrably reduced setup time without omitted checks.

## Release, update and rollback

Trusted source changes and a weekly schedule build candidate images, run smoke
tests and security scans, and publish immutable revision tags after authority is
established. Renovate/native update tooling proposes changed inputs; scheduled
rebuilds refresh the pinned toolchain's OS packages, while runtime/tool upgrades
remain reviewed changes. Vulnerability databases update independently and their
freshness is reported. Record source revision, tool versions, image digest,
architecture and scan evidence. Retention preserves all consumed/rollback
digests and bounds unreferenced candidates.

Rollout order: runtime compatibility and image candidates; authorized registry
publication; candidate workflow PR/canary; cache improvements; measured
promotion. Tasks can prepare source in parallel but cannot consume unpublished
digests. PR reporting requires an explicitly authorized real test PR.

Rollback restores previous workflow image digests, runtime pins and runner
configuration, with cache namespace invalidation when ABI changes. Keep previous
images and config backups. Test rollback on the canary before broad promotion.
Do not erase shared caches or registry data as a diagnostic shortcut.

## Open decisions

- Exact native build executor and permission scope for scheduled publication.
- Actual current Campsite runner identity and registry storage throughput.
- Supported native dependency-cache backend and retention/storage budget.
- Acceptable queue/setup latency after baseline measurement; warm-worker cost.
- Reviewdog behavior and trusted publisher mechanism on installed Forgejo.
- Latest release/image availability and runtime compatibility at execution time.

Homelab `README.md` requires exact target, commands, operator confirmation and
rollback before real-host mutation. Planning does not grant that confirmation.
Commit, push, image publication, provider dispatch and application deployment
remain separately evidenced steps.
