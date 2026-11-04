# First four priorities: implementation and acceptance

Update 2026-11-04: the user authorized replacing the remaining Elasticsearch code. See [PostgreSQL search migration](../deployment/postgresql-search.md). The earlier Elasticsearch blocker below is historical.

The [security and CI follow-up](security-ci-follow-up-2026-11-04.md) records the
subsequent deployment, full PostgreSQL test pass, authenticated browser
collaboration/search checks and current Forgejo results. The status statements
below describe the initial implementation checkpoint and are retained as history.

Tracking: `campsite-29q`. No commit, push, deployment, or branch-protection change performed.

## Implemented

- Styled-text startup rejects missing/blank authentication configuration. Authentication precedes body parsing; HTML conversion validates its input. Regression tests explicitly exercise `Bearer undefined`, invalid credentials, valid credentials, and health checks.
- Added frontend/realtime Forgejo workflow: frozen install, typechecks without declaration generation, lint, unit tests, Redis integration tests, and production builds. It reuses the established runner/bootstrap conventions. Remote execution is unverified.
- API CI now runs a serialized MySQL/PostgreSQL matrix, with PostgreSQL 18 matching the documented homelab major. PostgreSQL test host/user/password are configurable for service-container networking. Both database services start in each lane; this favors simplicity but consumes additional runner memory.
- Browser assertions are awaited and poll fixture text is unique. The legacy poll test remains explicitly skipped because its UI flow has not been validated against the current application. Added active shared-note reload coverage and a sync persistence retry regression retaining edits made during an API outage.
- Corrected the stale instruction claiming the repository has no CI.

## Verified locally

- Web: 200 unit tests passed.
- Styled-text: 29 tests passed.
- Sync: 58 tests passed with local Redis, including integration tests.
- Typechecks: web and sync passed; styled-text passed with declaration generation disabled (its ESLint config otherwise triggers an unrelated declaration portability error).
- Production builds passed: 7 Turbo tasks successful (4 cached). Existing CSS/Sentry configuration warnings remain.
- Lint passed after correcting blank-line violations in the changed test files; the full web lint run identified only those violations.
- Workflow YAML and database ERB/YAML parsed successfully.
- Playwright discovered the new test; discovery is not browser execution.

## Pending acceptance — not complete

- Execute the PostgreSQL Rails suite: no server responds on the configured local test port; Docker daemon is unavailable.
- Execute browser tests against a disposable seeded full stack: the local app is not listening. The new browser scenario remains unverified and does not demonstrate process-restart durability or cross-user authorization.
- Broader browser flows (organization switching, permission denial, upload retry, active post lifecycle) remain to be added and validated; the legacy skipped poll test is not counted as coverage.
- Run both Forgejo workflows and inspect actual logs before requiring their statuses. This requires publishing the changes, which has not been authorized.
- Full-stack browser CI provisioning remains open; the new workflow covers unit/service integration checks, not authenticated browser execution.

The original recommendation report remains the dated assessment. This implementation note records partial delivery and does not claim all four priorities have passed acceptance.

## Local PostgreSQL follow-up

Homebrew PostgreSQL 18.6 is running on port 5432. Created the separate
`campsite_api_test_pg` database and loaded its schema successfully. Existing
`campsite_api_development` and `campsite_api_test` were left alone.

Use `script/test-postgresql db:create db:schema:load` for initial setup and
`script/test-postgresql test` to run the suite. The wrapper selects the pinned
Ruby, clears production database/key overrides, and defaults to the local user
and serial execution. Parallel native pg testing crashed during fork on this Mac.
The serial suite reached initialization but is blocked by missing local
Elasticsearch at localhost:9200. PostgreSQL setup is complete; suite acceptance
remains pending Elasticsearch availability.
