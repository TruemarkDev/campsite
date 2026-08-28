# Maintenance Policy

Campsite is published **as-is**. The original company is gone and there is no active
product team. This repository is in **stewardship mode**, not development mode.

The only goals are:

1. **Stay buildable** — the app continues to build and boot with a current toolchain.
2. **Stay secure** — known CVEs in dependencies get patched.
3. **Stay self-hostable** — local-dev and self-hosting paths keep working.

No new features. No redesigns. No speculative refactors.

---

## Allowed changes

- Security patches and patch/minor dependency bumps that keep CI green.
- Toolchain/version-file reconciliation (Node, Ruby, lockfiles, Docker base images,
  CI runner versions) — keep them mutually consistent (see "Toolchain" below).
- Fixes for broken self-hosting / local-dev setup steps.
- Documentation fixes.

## Disallowed changes (open an issue instead of coding these)

- New features, screens, endpoints, or user-facing behavior.
- New dependencies (a security fix that _requires_ a new dep is an issue, not a PR).
- Behavior changes — including "fixing" a failing test by changing what the code does.
- Major-version upgrades that change framework APIs (Rails, Next, React, etc.), unless
  there is no supported/patched version remaining on the current major.
- Cosmetic refactors, reformatting, or renames unrelated to a security fix.

## The rule for AI-assisted maintenance

An agent may **merge** a dependency bump only when **all** hold:

- It is a security or patch/minor update (not a major).
- It adds no new dependency and changes no application code.
- The existing CI suites pass (`api-tests.yml`, `client-build.yml`,
  `styled-text-server-build.yml`).

If a fix would require a behavior change, a new dependency, or a major upgrade:
**stop and open an issue** describing the advisory and the options. Do not implement it.

Local test, lint, and build gates are the source of truth. Green-stays-green ⇒ safe & mechanical. Otherwise ⇒ escalate.

---

## Toolchain

These four must always agree. When bumping one, bump all:

| Where          | File                                                                                |
| -------------- | ----------------------------------------------------------------------------------- |
| mise root      | `mise.toml`                                                                         |
| mise api       | `api/mise.toml`                                                                     |
| Ruby pin       | `api/.ruby-version` (symlinked from `/.ruby-version`)                               |
| Node engines   | `package.json` → `engines.node`                                                     |
| Container base | `apps/*/Dockerfile` → `FROM node:*`; API uses `api/Dockerfile` → `ARG RUBY_VERSION` |

Current baseline: **Node 24.x, Ruby 4.0.6.**

## Automated watchdog

❌ No repository-owned dependency-update automation is configured. Dependency and
security updates require an operator-run review.
