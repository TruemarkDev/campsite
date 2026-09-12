# Beads Board review evidence — 2026-09-12

This records verification of the uncommitted completion changes on
`codex/beads-board-current-base`, based on
`976b2b7eebb8d31feaabcc8961f4f2242be5416e`. The implementation already present
at that baseline is part of the reviewed feature. No commit, merge, push,
remote Beads sync, or deployment is included.

The [OpenSpec requirements](../../../openspec/changes/add-channel-beads-board/README.md)
remain authoritative. This is an evidence index, not another requirements
source. [Operator instructions](../beads-board.md) describe the implemented
publisher and release boundary.

## Requirement coverage

| Contract                           | Evidence                                                                                                                                                                                                                                     |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SyR-1 pairing and source lifecycle | Publisher controller tests cover channel binding, expiry, reuse, revoked initiator, replacement, archive, and exact connector. Policy tests require explicit membership. Browser trials pair both channel formats and detach through the UI. |
| SyR-2 atomic/versioned ingest      | Snapshot model tests cover malformed primitives, unknown fields, digest, idempotency, older collections, immutability, pointer ownership, and event recipients. Rejected input preserves the last snapshot.                                  |
| SyR-2a membership                  | Board/publisher controller and policy tests cover human, guest, OAuth reader, and nonmember restrictions. Browser API trials show public channel access with Board denial.                                                                   |
| SyR-3 read-only authority          | Rails serves stored snapshots. Publisher tests constrain native commands; the real fixture retained its revision, export, Git state, and all 79 file hashes after collection and failed publication.                                         |
| SyR-4 columns                      | Native fixture contains one issue in each of five columns. Schema/publisher tests reject conflicting classifications; web tests preserve Deferred and progressively reveal Closed.                                                           |
| SyR-5 navigation                   | Desktop browser trials exercise shortcut 4 for posts and 3 for chat. Pending setup omits Board; detach and disabled flags return to the channel root. Mobile controls remain visible.                                                        |
| SyR-6 safe metadata                | Explicit serializer/schema allowlists, generated-client inspection, markup-as-text component tests, publisher stripping/UTF-8 tests, and secret scanning.                                                                                    |
| SyR-7 freshness                    | Waiting and populated states, original revision/timestamps after rejected ingest, and browser refresh failure with last-good cards retained.                                                                                                 |
| SyR-8 filters                      | Component tests cover the supported filters and Closed pagination. Browser trials exercise title and Closed filters without task writes.                                                                                                     |
| SyR-8a lifecycle/export            | Model cleanup tests, browser archive/unarchive and detach, and an archive-job regression that opens the produced ZIP and checks exclusion.                                                                                                   |
| SyR-9 classification               | Default-false model, admin-only update tests, and roster tests for classification removal, generic integrations, publisher role, and attachment removal.                                                                                     |
| SyR-10 safe roster                 | Dedicated summary serializer and response schema; membership denial tests and safe-field assertions.                                                                                                                                         |
| SyR-11 attachment labels           | Inspected roster labels and desktop screenshots show Attached; token activity is not used as presence.                                                                                                                                       |

## Automated gates

The declared toolchain was used: Ruby 4.0.6, Node 24.19.0, pnpm 11.9.0.
Direct Node invocation avoids selecting a different Node bundled with a CLI.

| Gate                                         | Result                                                                     |
| -------------------------------------------- | -------------------------------------------------------------------------- |
| Full Rails suite                             | 4,249 tests, 13,956 assertions, zero failures/errors/skips; 960.7 seconds. |
| Focused Rails API/model/policy/OAuth/export  | 53 tests, 280 assertions, passed.                                          |
| Additional lifecycle regressions             | 16 tests, 126 assertions, passed.                                          |
| Earlier full-suite failure files after fixes | 149 tests, 574 assertions, passed.                                         |
| Publisher                                    | 9 tests, 48 assertions, passed.                                            |
| Full web suite                               | 44 files, 186 tests, passed.                                               |
| TypeScript                                   | `tsc --noEmit --incremental false`, passed.                                |
| Web production build                         | `node node_modules/next/dist/bin/next build`, passed.                      |
| Rails assets                                 | `bundle exec rails assets:precompile`, passed.                             |
| Migration                                    | Separate empty database schema load and down/up roundtrip passed.          |
| Client generation                            | `script/gen-client` completed; generated client was not hand-edited.       |

The initial full Rails run exposed serializer query-count regressions. The
permission field now uses the existing membership preload. A member-role test
also incorrectly used the factory's default admin role; it now explicitly uses
the member trait. An unrelated backfill timing failure passed on rerun.

The first asset build encountered a disposable pnpm esbuild launcher that sent
a native binary to Node after postinstall replaced its target. Relinking that
ignored `api/node_modules/.bin/esbuild` to its native executable allowed the
unchanged build to pass. No manifest or lockfile was changed. The web build
reported existing CSS optimizer and missing Sentry upload-token warnings;
compilation and prerendering completed successfully.

## Browser evidence and reproduction

- [Post channel desktop](post-desktop.png)
- [Chat channel desktop](chat-desktop.png)
- [Mobile at 390 × 844](mobile.png)
- [Browser assertions](proof.json)
- [Native publisher non-mutation proof](publisher-proof.json)

`script/verify-beads-board-browser.mjs` uses the existing Playwright dependency
and a separate headless browser. It does not attach to the user's browser or
save authentication state. It seeds a disposable local test database and calls
the real publisher against a disposable `campsite-beads-fixture-*` repository.
It requires API/web test servers on ports 13001/13000 with matching
`api.campsite.test`, `auth.campsite.test`, and `app.campsite.test` URLs. The API
test server must use the ActiveRecord Flipper adapter, fake Sidekiq, and disabled
Searchkick callbacks; this allows the trial to exercise flag rollback without
external services. The fixture repository needs ordinary Ready, In progress,
Blocked, Deferred, and Closed issues. Reusing this harness changes only the
explicit disposable database's fixture organization and cached source records.

```bash
BEADS_BOARD_UAT_DATABASE=campsite_beads_board_uat \
BEADS_BOARD_FIXTURE_REPOSITORY=/path/to/campsite-beads-fixture-review \
BEADS_BOARD_RUBY=/path/to/ruby-4.0.6/bin/ruby \
PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/path/to/chromium \
node script/verify-beads-board-browser.mjs
```

🟡 Accessibility evidence covers keyboard navigation, labeled controls and
scrolling regions, mobile geometry, and reduced-motion rendering. A human
screen-reader session has not been performed; no screen-reader conformance is
claimed. Realtime delivery through a deployed Pusher service also remains a
release check; local tests cover private-channel event production and query
invalidation.

## Review and release boundaries

The main checkout contains separate uncommitted pagination and chat work.
These changes were preserved. Integration with that work has not been
performed, so merge readiness against those uncommitted edits is unproven.
Review the feature branch's existing commits as well as this completion diff.

No production acceptance or homelab release is claimed. Deployment needs
separate authorization and exact API/web revision verification. The local
trial disabled the feature and verified unchanged Beads revision/export.
Automatic historical-snapshot pruning is unbuilt; storage grows until source
detach or channel deletion. No new dependencies, scheduler, or task-write
capability were introduced.

Tracking: `campsite-qrd` is closed for this worktree completion. Separate
follow-ups are `campsite-b4r` (release/human acceptance) and `campsite-e5o`
(retention policy). Temporary API/web servers and the test Elasticsearch
container were stopped after verification. Disposable local databases and the
Beads fixture remain available for reproducing the review.
