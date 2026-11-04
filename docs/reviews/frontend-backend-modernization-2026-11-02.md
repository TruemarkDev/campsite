# Campsite frontend and backend modernization recommendations

Implementation follow-up: [PostgreSQL history, API generation and failure coverage](reliability-follow-up-2026-11-04.md) records the subsequent changes, passing checks and live acceptance limits. This report remains the dated assessment.

CSP follow-up: [report-only script policy and validation](../deployment/content-security-policy.md). Enforcement remains gated on compatibility observations.

Date: 2026-11-02. Checkout: `main`, baseline `2f0416b`, with pre-existing local changes. Scope: this repository only. Tracking: `campsite-b6h`.

## Assessment

The application's age is not a good proxy for its current technical quality. The checkout already declares Next.js 16, React 19, Tailwind 4, TanStack Query 5, and Rails 8.1 defaults. Shared TypeScript configuration already enables `strict`. It has generated API types, Pundit authorization, security scanners, rich-text sanitization tests, and collaborative editing tests. Preserve these investments.

The best next investment is stronger verification of the existing architecture, followed by focused simplification. A frontend rewrite, backend language change, or wholesale adoption of new framework features would introduce substantial risk without an established user benefit.

This is a sampled static review, not an exhaustive security audit or performance benchmark. No application tests, builds, authenticated browser checks, or live infrastructure probes were run. Dependency declarations were inspected; this report does not certify that every resolved package is the latest release or vulnerability-free. Current primary guidance was consulted for the architectural recommendations below.

## Priority summary

Effort is relative: S = localized change, M = several connected changes, L = cross-service work. These are estimates, not schedules. P1 means address early; P2 means follow after the baseline is reliable; P3 means optional investigation.

| ID | Priority | Recommendation | Effort | Evidence status |
|---|---|---|---|---|
| TD-1 | P1 | Reject missing styled-text service credentials at startup | S | Confirmed source-level failure mode; live exposure unknown |
| TD-2 | P1 | Add frontend and realtime gates to existing CI | M | API workflow present; frontend gates absent from that workflow |
| TD-3 | P1 | Exercise PostgreSQL compatibility in CI | M | PostgreSQL configuration exists; inspected CI uses MySQL |
| TD-4 | P1 | Repair and expand browser regression coverage | M | Concrete missing `await` and non-unique fixture in existing test |
| TD-5 | P2 | Tighten production CSP with a compatibility rollout | M | Broad script exceptions confirmed |
| TD-6 | P2 | Test API generation and cache consistency together | M | Generated client and manual invalidation coexist |
| TD-7 | P2 | Verify collaborative editing under failure and revocation | L | Persistence and schema protections exist; end-to-end guarantees unverified |
| TD-8 | P2 | Establish job retry and transaction guarantees | M | Native Sidekiq configuration inspected; job-wide audit pending |
| TD-9 | P2 | Turn existing performance instrumentation into decisions | M | Instrumentation exists; measured baseline unavailable |
| TD-10 | P2 | Add accessibility acceptance to core workflows | M | Existing keyboard tests are useful but not a conformance assessment |
| TD-11 | P2 | Retire compatibility exceptions deliberately | S–M | Dated cleanup notes and runtime/type mismatch present |
| TD-12 | P3 | Pilot App Router only for a justified route | M–L | Main app uses Pages Router; migration benefit unmeasured |

## Backend and service boundaries

### TD-1 — Fail closed when styled-text credentials are missing

Evidence: `apps/styled-text-server/src/app.ts` compares the request header with ``Bearer ${process.env.AUTHTOKEN}``; `src/index.ts` starts listening without validating that variable. If it is unset, the literal header `Bearer undefined` matches. This is a conditional authentication bypass in the source; this review did not establish that any deployed instance lacks the token.

The service SHOULD reject startup when the token is absent, empty, or whitespace-only. Verification: Test startup with each invalid configuration; test that a configured service rejects absent and incorrect headers and accepts only the configured credential.

The service SHOULD validate conversion payloads consistently. `/html_to_slack` destructures `html` without the type checks applied to `markdown` in the adjacent route. Authentication SHOULD precede expensive parsing where practical, with explicit body limits and structured errors. Verification: Test malformed JSON, missing fields, incorrect types, oversized input, and ordinary conversion fixtures. Preserve `/up` as a deliberate health-check exception.

### TD-3 — Make the database test environment representative

Evidence: `api/config/database.yml` supports PostgreSQL in production and a separate PostgreSQL test mode; `.forgejo/workflows/api-tests.yml` provisions MySQL and does not select that test mode. MySQL success alone cannot establish PostgreSQL behavior for migrations, SQL, indexes, locking, or serialization.

CI SHOULD run the database used by the declared deployment, retaining a second adapter lane only while both are intentionally supported. Verification: Test schema loading, migrations, search, concurrent writes, and representative controller flows on the chosen adapter. The PostgreSQL test configuration currently hardcodes loopback; a service-container lane will also need configurable host and credentials. Determine the actual release target before deciding which adapter is primary; no live database was inspected here.

### TD-8 — Make retries and transaction boundaries explicit

Evidence: `api/config/initializers/sidekiq.rb` enables strict arguments and custom client/server middleware. Controllers use native `perform_async`; this is not proof of Active Job transaction behavior. The inspected initializer does not enable transactional push, but individual callers may already use safe callbacks.

High-impact jobs SHOULD have documented idempotency and enqueue-after-commit behavior. Verification: Test transaction rollback, duplicate delivery, worker interruption after an external side effect, and retry recovery. Begin with notifications, exports, and integration writes; audit their actual call sites before selecting fixes. Introduce an outbox only where durable database-to-queue delivery is required and existing mechanisms do not meet that need. Keep Sidekiq unless measured requirements justify replacement. [Sidekiq guidance](https://github.com/sidekiq/sidekiq/wiki/Best-Practices).

## Frontend reliability and experience

### TD-4 — Repair browser tests before expanding migration scope

Evidence: `apps/web/playwright/example.spec.ts` ends with `expect(post).not.toBeVisible()` without `await`, and explicitly notes that repeated fixture text makes the selector ambiguous. The AI note-editing spec exercises two pages but mocks the AI response; it does not prove the real provider integration.

Browser tests SHOULD await asynchronous assertions and create unique, isolated fixtures. Verification: Test repeated and parallel runs, and deliberately prevent deletion to confirm the assertion fails reliably.

The regression suite SHOULD cover sign-in, organization switching, permissions, post creation/deletion, upload failure/retry, and collaborative note reconnects. Verification: Test those flows against a controlled full stack with disposable data. Keep mocked provider tests, with a separately bounded integration test where real service behavior matters.

### TD-5 — Reduce production script exceptions safely

Evidence: `apps/web/next.config.js` applies `script-src 'unsafe-inline'` and `'unsafe-eval'` globally. Comments attribute them to hydration and 100ms noise cancellation. These are compatibility explanations, not proof that the exceptions remain necessary across every route.

The application SHOULD evaluate nonce-based script authorization and isolate unavoidable SDK exceptions. Verification: Demonstration in report-only mode across authentication, editor, calls, embeds, and desktop use; then Test enforced policy on the same flows. Account for nonce implications for rendering and caching. Do not simply delete the exceptions and break calls. [Next.js CSP guidance](https://nextjs.org/docs/13/pages/building-your-application/configuring/content-security-policy).

### TD-6 — Make server state ownership easier to maintain

Evidence: `apps/web/hooks/useArchiveProject.ts` invalidates a broad project-list key, a scoped detail key, and manually updates membership state. `apps/web/utils/queryClient.ts` supplies typed cache helpers, while `utils/normy/` contains additional normalization machinery and tests.

New mutations SHOULD follow one documented ownership pattern for query keys, invalidation, optimistic changes, and rollback. Verification: Test that list, detail, membership, and realtime views converge after success, rejection, organization changes, and reconnects. This is a consistency recommendation, not a demonstrated stale-cache bug. Preserve the existing typed helpers; consolidate only after mapping consumers.

API changes SHOULD regenerate the client and fail CI on unexplained generated differences. Verification: Test `script/gen-client` in a reproducible environment and inspect the resulting diff. Never hand-edit `packages/types/generated.ts`.

### TD-9 — Measure before changing rendering architecture

Evidence: `_app.tsx` contains optional Web Vitals reporting; `next.config.js` supports bundle analysis and disables Next image optimization. Rails' base controller enables Prosopite outside production. These are useful starting points, not evidence that the application is fast or slow.

The project SHOULD collect a baseline for inbox navigation, long feeds, editor typing, image loading, API query counts, and slow requests before setting budgets. Verification: Analysis of representative traces and bundle reports, followed by comparison under the same workload. Agree targets after measurement; this report invents no SLA. Check whether the configured image CDN already provides transformations before enabling a second optimizer.

### TD-10 — Validate accessibility as a user workflow

Evidence: keyboard shortcut and layered-hotkey tests exist under `components/CommandMenu/__tests__/`. They do not establish full accessibility of dialogs, menus, editors, or mobile layouts.

Core workflows SHOULD target WCAG 2.2 AA, with keyboard-only operation, focus restoration, visible focus, zoom/reflow, accessible names, error announcements, and touch targets included. Verification: Test automated checks plus manual keyboard and screen-reader demonstrations on the actual app. Treat conformance as unverified until evaluated. [W3C WCAG 2.2](https://www.w3.org/TR/WCAG22/).

### TD-12 — Use App Router as an optional incremental improvement

Evidence: `apps/web/pages/_app.tsx` owns per-page providers and app startup behavior. Shared auth, TanStack Query, collaboration, and desktop compatibility make a full routing migration substantial.

A pilot MAY migrate one low-risk route when server rendering or reduced client JavaScript offers a measured benefit. Verification: Test auth, navigation, provider/cache lifetime, and desktop behavior, and compare bundle/performance measurements. Keep Rails as the authorization authority and avoid introducing a second competing data layer. Next.js supports incremental coexistence of the routers. [Official migration guidance](https://nextjs.org/docs/pages/guides/migrating/app-router-migration).

## Cross-stack engineering improvements

### TD-2 — Extend existing CI rather than rebuilding it

Evidence: `.forgejo/workflows/api-tests.yml` already runs bundler-audit, Brakeman, RuboCop, schema loading, asset compilation, and Rails tests. The project instructions incorrectly say no CI is checked in. The inspected workflow does not run web typechecking, frontend tests/builds, sync-server tests, or styled-text tests. Remote execution and branch protection were not inspected.

CI SHOULD add bounded frontend and realtime jobs with frozen dependency installation, explicit typechecking, linting, unit tests, production builds, and a small browser smoke suite. Verification: Demonstration on an actual Forgejo run, including a deliberately failing gate before making it required. Keep resource limits appropriate to the runner; avoid running every heavyweight suite concurrently. Documentation SHOULD describe the workflow actually present. Verification: Inspection against checked-in workflows and observed runs.

### TD-7 — Protect collaborative documents across service failures

Evidence: `apps/sync-server/src/database.ts` persists Yjs state and rendered HTML through Rails, chooses canonical state after concurrent initialization, and makes older-schema clients read-only. Existing sync tests cover database, Redis, coordination, and lineage paths. These protections deserve preservation.

Cross-service tests SHOULD demonstrate recovery after Rails unavailability, sync-process restart, expired credentials, permission revocation, and concurrent human/agent edits. Verification: Test persisted document equivalence after reconnect, rejection of revoked writes, and compatibility during staggered deployments. Define what the UI means by “saved” and measure potential loss before claiming durability. Existing unit coverage does not establish every failure scenario end to end.

### TD-11 — Maintain a small, deliberate compatibility surface

Evidence: `pnpm-workspace.yaml` carries security floors, editor version pins, release-age exceptions with removal dates, and Node 26 types while the root manifest targets Node 24. `_app.tsx` still calls a draft-cleanup hook marked for deletion after April 2024. `api/Gemfile` obtains `ruby_llm` from upstream `main`; the lockfile can pin a revision, but subsequent updates can advance it.

Dependency maintenance SHOULD align Node types with the supported runtime, review aged exceptions, and record the compatibility reason for each retained override. Verification: Inspection of the registry and lockfile followed by affected tests/builds. Do not remove editor pins merely because they look old; their comments describe concrete compatibility problems.

The draft-cleanup hook SHOULD be retired only after checking whether old local drafts still require it. Verification: Test representative old storage payloads and current drafts. Git-sourced dependency updates SHOULD review the resolved commit and migration impact; a stable release MAY replace the branch dependency once required functionality is available. Verification: Inspection of upstream changes and focused integration tests.

## Suggested sequence and boundaries

1. Address TD-1, repair the browser assertion, and reconcile the CI documentation.
2. Establish frontend/realtime gates and production-adapter coverage; verify green runs before requiring them.
3. Add cross-service document and job-failure tests, API generation checks, and cache convergence coverage.
4. Collect performance/accessibility baselines and stage CSP hardening.
5. Retire validated compatibility debt; consider the routing pilot only if evidence supports it.

Do not replace Rails, Sidekiq, TanStack Query, or the editor stack solely because the original product is several years old. Do not adopt microservices, GraphQL, Server Actions, or a new state library without a concrete problem they solve here.

Existing requirements remain authoritative in `openspec/changes/`, including `add-ai-note-editing`, `add-mcp-2fa-enforcement`, and `homelab-native-private-data-exports`. This report is advisory and does not duplicate or override their acceptance criteria. Any approved implementation should reconcile with the relevant proposal first.

Open questions: Which CI checks actually pass and block merges? Which database adapter is the release acceptance target? Are styled-text credentials always populated? What performance and accessibility baseline do users experience? What durability guarantee should “saved” represent during a sync outage? These require verification; source inspection alone cannot answer them.
