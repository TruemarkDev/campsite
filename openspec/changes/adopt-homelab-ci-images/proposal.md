## Why

Campsite CI installs operating-system packages, Node and pnpm on every API
run. Static checks share the service-backed test job. Shared prebuilt images
in the existing homelab Forgejo registry can remove repeated setup while
preserving project-owned dependency versions and adding reliable PR feedback.

The user selected reviewdog, the existing private registry, and latest stable
Ruby and Node.js. This proposal incorporates those choices together.

❌ Unbuilt: this change is a plan. No runtime upgrade, image publication,
runner change, cache rollout or application deployment has been performed.

## What Changes

- Homelab owns versioned CI images, their build workflow, smoke tests, public
  CA trust and update policy. Forgejo at `git.home` hosts the published images.
- Campsite adopts latest stable Ruby and Node.js consistently across local
  development, CI and application image sources. Planning candidates verified
  on 2026-09-24 are Ruby 4.0.7 and Node.js 26.10.0 Current; implementation
  rechecks official releases. Latest stable includes Node Current, not only LTS.
- Campsite consumes immutable CI image digests and separates static/security
  analysis from service-backed tests. reviewdog publishes findings to PRs.
- Dependency caching and runner image delivery receive measured, bounded
  improvements. Keeping a runner warm and changing concurrency remain capacity
  decisions, not assumptions built into this proposal.

## Capabilities

### New Capabilities

- `homelab-ci-images`: reproducible shared image lifecycle, runtime parity,
  PR feedback, cache isolation and measured adoption.

### Modified Capabilities

None.

## Impact

- Homelab source: proposed `docker/ci-images/`, `.forgejo/workflows/ci-images.yml`,
  existing runner ownership paths, and a runbook linking this specification.
- Campsite source: toolchain/version declarations, engines, application
  Dockerfiles, affected lockfile metadata, baseline documentation and Forgejo
  workflows. Application dependency upgrades are limited to compatibility needs.
- Existing issues remain authoritative for their work: `campsite-jc3` owns
  Brakeman ignore selection; `campsite-7b6` owns the application builder cache
  repair; `campsite-au5` owns the pruned web build failure.
- Beads epic `campsite-7e3` owns execution tracking. This OpenSpec change owns
  requirements; design.md owns proposed implementation choices. If a task
  conflicts with requirements, update/review the specification before execution.
- Source implementation and image publication do not authorize production
  deployment, runner host mutations, registry migration or increased capacity.
