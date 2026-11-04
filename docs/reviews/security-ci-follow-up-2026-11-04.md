# Security and CI follow-up — 2026-11-04

✅ Security remediation is deployed. Final API/frontend CI and the exercised
authenticated note collaboration/search lifecycle passed.

Tracking: `campsite-8am` and `campsite-29q`. This follows the
[PostgreSQL search release](postgresql-search-release-2026-11-04.md).

## Dependency changes

The official RubyGems registry was checked before resolving a conservative,
named dependency update. The nine gems reported by the earlier Forgejo audit
were updated; unrelated application dependencies were retained.

| Gem                  | Previous lock                 | Updated lock   |
| -------------------- | ----------------------------- | -------------- |
| addressable          | 2.9.0                         | 2.9.2          |
| crass                | 1.0.7                         | 1.0.8          |
| css_parser           | 3.0.0                         | 3.4.0          |
| loofah               | 2.25.2                        | 2.25.3         |
| nokogiri             | 1.19.4                        | 1.19.7         |
| rack                 | 3.2.7                         | 3.2.8          |
| rails-html-sanitizer | 1.7.1                         | 1.7.2          |
| ruby_llm             | Git revision declaring 1.16.0 | RubyGems 2.1.1 |
| trilogy              | 2.13.0                        | 2.13.2         |

RubyLLM now resolves from its published stable gem with `~> 2.1`, rather than
following upstream `main`. The application already had its newer response/token
compatibility handling. The focused LLM suite passed three tests and 11
assertions against the published version using stubbed completions. Live
provider completion behavior was not verified.
See [the official release notes](https://github.com/crmne/ruby_llm/releases/tag/v2.1.1).

The tracked gem cache was refreshed to match the lockfile. RubyLLM's unused
`event_stream_parser` dependency was removed by resolution.

## Security and CI checks

✅ Local dependency audit with a fresh advisory database reported no
vulnerabilities. Database commit: `adeaf1283ee64aae48bb61150a773283ff285175`.

✅ RuboCop inspected 1,703 Ruby files with zero offenses.

✅ Strict Brakeman completed with zero unsuppressed warnings, zero errors and
zero obsolete ignore entries. Its four reviewed false positives have individual
explanatory notes in `api/config/brakeman.ignore`:

- scheduled-notification SQL composes fixed fragments and binds time values;
- cursor pagination validates/quotes column names, allows fixed directions,
  and binds cursor values;
- export downloads authorize the export before redirecting to an SDK-generated
  S3 URL with a trusted configured endpoint;
- mention links synthesize URLs from the trusted application origin and paths.

The previous `api/.brakeman.ignore` was not in Brakeman's default lookup
location. It was replaced with the documented configuration path, and obsolete
fingerprints were removed. Strict note/obsolete-entry checks remain enabled;
the dependency audit was not bypassed.

The runner bootstrap uses a job-owned CA bundle, the checksummed official pinned
Node binary and Python for native Node module compilation. The earlier failed
run IDs and errors remain in the original release report.

✅ The full updated local PostgreSQL suite passed 4,287 tests and 14,041
assertions with zero failures, errors or skips (569.48 seconds, two processes).

Forgejo run 21 passed dependency audit, strict Brakeman, lint, schema load and
asset compilation, then finished all 4,287 tests with one error: the runner
lacked `/usr/bin/zip` for the archive test. Run 22 installed native Node modules
successfully after Python was added, then failed to resolve the unbuilt
`@campsite/regex` package during typechecking.

The API workflow now installs `zip` and `unzip`. The frontend workflow now builds
the shared workspace prerequisite graph through Turbo before direct typechecks
and unit tests; those commands do not otherwise execute Turbo's `^build` rule.
The graph build and sync/styled-text typechecks passed locally.

API run 25 at `870324d8a7881ef8e724ae7b692a53ef2001ff4c` confirmed the archive
error was fixed, but exposed a nondeterministic assertion in the webhook update
test: the unordered association returned the same two URLs in reverse order.
The test now compares the URL set, checks the active count, and checks event
types on explicitly identified existing/new webhooks instead of `first`/`last`.
No application ordering contract was changed.

✅ Frontend run 26 passed all gates, including workspace builds, typechecks,
lint, unit/realtime tests and production builds.

The corrected webhook controller suite passed locally: 18 tests, 45 assertions,
zero failures/errors/skips, and clean targeted RuboCop. Commit
`73dca1c26d9a32fc0d3e50a512ceb30e6d2fdd8f` pushes that fix for the final CI
run. ✅ [API CI run 27](https://git.home/tokdio/campsite/actions/runs/27) passed
all gates and the full Rails suite. ✅ [Frontend CI run 28](https://git.home/tokdio/campsite/actions/runs/28)
also passed every gate, including production builds. Only CI
configuration and test assertions changed after the deployed application
revision; the application/model/library/dependency and frontend trees match.

## Authenticated browser verification

✅ Using a dedicated minimized Brave window at `https://camp.home`, the existing
authenticated session completed these live checks against API revision
`77a7bdc1874bbf40b0244ca83b0d3b446c100a4e`:

1. Created a uniquely labeled temporary document and edited its title and body.
2. Opened a second independent tab on that document and observed both changes.
3. Closed the second tab, reloaded the author tab, and observed persisted content.
4. Found the temporary document in native search through the browser.
5. Deleted it through the UI and verified its search result disappeared.
6. Independently confirmed the synthetic title/body reached the API canonical
   note row and that it was discarded and excluded from native search afterward.

Only the temporary acceptance document was changed. Browser credentials,
cookies, recordings and storage state were not exported. The temporary document
is soft-deleted under the application's normal behavior.

These observations establish the exercised note/search/collaboration flow.
They do not establish coverage for every private-resource UI permission,
mentions or transcript scenario, nor do they execute the entire Playwright suite.
The reproducible isolated fixture stack and broader Playwright matrix were
tracked separately as `campsite-cnh`; the completed local verification is below.

✅ After the security deployment below, a fresh temporary document repeated
title/body creation, two-tab viewing, search, and reload persistence. An
additional edit sent while both tabs were already connected appeared live in
the collaborator tab. Closing that tab and reloading the author preserved the
additional edit, establishing the exercised live-update path as well as initial
document loading. Its search result appeared; it was deleted through the UI.
An independent API check confirmed the additional live edit was persisted in
the canonical row and the discarded note was excluded from search afterward.

## Release status

✅ Security revision `039d0fe39642f892d73ce0203f12def4bb1c3448` is pushed to
Forgejo and deployed to API, worker and export worker on Quill through Kamal.
API deployment completed in 16.4 seconds; worker deployment in 24.6 seconds.
The running API and worker independently verified all nine patched gem versions. All three
containers reported zero restarts at initial verification.

| Service           | Registry manifest digest                                                  | Running image ID                                                          |
| ----------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| API               | `sha256:37b92e5c01956ad62ccf9f8a1bcbe5b6476522956d5608becb91bf8da27a5a0b` | `sha256:9c062151565638e8135197518b234bbdfa87b3546ff037227f62b7c4bb4263cc` |
| Worker and export | `sha256:4728db87ffe0d9a11b659ad134a2a3e68a0dbf4f0b35b7f5021b9d387a20d1e6` | `sha256:f14e1744694ab1d2f3762a82f1956f62f8d866a490ce16537394e499c2524ff1` |

The fresh pgBackRest checkpoint is `20261031-194502F_20261104-045035I`;
backup and subsequent WAL archive checks passed. No database schema change was
required. Styled-text, web and sync were not redeployed. HTTPS API health,
sign-in and homepage checks returned 200; native search health and authenticated
API-to-styled-text conversion passed after deployment.

The previous native PostgreSQL revision `77a7bdc1874bbf40b0244ca83b0d3b446c100a4e`
remains the rollback application revision. Elasticsearch is not part of this
release and was not started or restored.

## Reproducible browser matrix follow-up

✅ `pnpm test:browser` provisions a disposable native PostgreSQL database and
per-run Redis synchronization prefix, starts four local services, and runs six
active Chromium scenarios. Two consecutive complete runs passed (35.6 seconds
and 1.3 minutes); the second used a fresh isolated Next cache. No scenarios were
skipped or retried. Both databases were dropped, and a subsequent PostgreSQL and
Redis inspection found no fixture databases or synchronization keys remaining.
No real-user browser state was exported. See
[`apps/web/playwright/README.md`](../../apps/web/playwright/README.md) for the
command, prerequisites, isolation boundaries and cleanup limits.

The matrix covers AI proposal propagation/rejection across clients, canonical
API note persistence and reload, dashboard, post creation/deletion, existing
poll editing/voting/reload, and independent private/read-only document permission
checks. The skipped obsolete poll-creation flow was replaced with supported
current behavior; poll creation is absent from the current composer.

The suite reproduced a Tiptap 3 editor lifecycle crash: a bubble-menu effect read
`editor.view.dom` while the view was unmounted. The fix binds and removes the
keyboard listener using editor mount/unmount events and guards destroyed editors.
The collaborative note cases pass with that correction. Web unit tests passed
(200), sync tests with native Redis passed (58, no skips), and targeted Ruby lint passed.
The exact committed source also passed all six browser cases from a separate
clean worktree using the pinned toolchain (56.1 seconds), with fixture cleanup
verified afterward. Web/sync typechecks, web lint, strict Brakeman and the staged
Gitleaks scan passed.
This is local fixture acceptance; it does not extend the historical live browser
observations above or establish that CI executes the browser matrix.

### Web follow-up release

✅ Commit `c913da23a54989fc3a9ef9135e5783e0a21e4654` is pushed to Forgejo.
[API CI run 29](https://git.home/tokdio/campsite/actions/runs/29) and
[frontend CI run 30](https://git.home/tokdio/campsite/actions/runs/30) passed
every gate. These workflows execute the Rails and frontend/realtime gates;
the six browser scenarios above were executed locally from the exact commit.

Kamal deployed only `campsite-web-home-staging` on Quill `192.168.10.32` as
operator `prakash`, using `config/deploy.campsite-web-home.yml` and the repository
deployment wrapper from a clean detached worktree. Promotion with
`kamal deploy --skip-push --version=c913da23a54989fc3a9ef9135e5783e0a21e4654 -c config/deploy.campsite-web-home.yml`
completed in 19.3 seconds after the CI gates passed.

The independently checked registry manifest is
`sha256:41edffae58c8603536502117311a06b44d8d213c567e65ead0ec563bd1c83f26`;
the running image ID is
`sha256:5ab91d22ac819cc2bdc6cc9fb756aa7d7c0562ab3c9a7a38a698fc7bf6924d35`.
`https://camp.home/api/build-id` reports the exact deployed commit,
`/robots.txt` returns 200, and the container had zero restarts at verification.
The previous web revision is `b109a4dccd7f7a9b187099d71ab459ef95315d4f`;
its registry manifest remains available. Roll back through the same wrapper
with `kamal rollback b109a4dccd7f7a9b187099d71ab459ef95315d4f -c config/deploy.campsite-web-home.yml`.
No API/worker/sync/styled-text service or database schema was changed by this
web-only promotion. The two pre-existing local frontend edits were excluded.

✅ Authenticated live acceptance on the new web revision used a dedicated
minimized Brave window after the user signed in manually. A single temporary
document accepted title/body edits; a separate canonical API read returned both
saved values. Reload preserved both values and the editor remained editable.
Selecting its text and invoking Cmd+K opened the link editor without losing the
document. The temporary document was then deleted through the UI confirmation
dialog; a subsequent API read returned 404. The task tab was closed afterward
without changing the frontmost application. Browser passwords, cookies and
storage state were not read or exported.
These live checks used one identity and one tab; the independent-member and
two-client scenarios were established by the isolated fixture matrix above.
