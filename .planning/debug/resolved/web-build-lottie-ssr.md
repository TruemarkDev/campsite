---
status: resolved
trigger: 'Next production build fails while collecting page data for /[org]/chat/new'
created: 2026-08-11T16:08:00+05:45
updated: 2026-08-11T23:22:29+05:45
---

## Current Focus

hypothesis: Confirmed and fixed: both browser-only Lottie import paths must be deferred during SSR.
test: Two Node-environment import regressions plus a full telemetry-disabled Next production build.
expecting: Human confirms the build result is sufficient verification for the packaging task.
next_action: Resolved and archived after explicit human confirmation.
bug_class: bohrbug
reasoning_checkpoint:
hypothesis: Both the upload utility and react-lottie-player eagerly load lottie-web during SSR.
confirming_evidence: The utility regression fails on revert, but the held-out build still reaches the identical lottie_light createTag failure through the component graph.
falsification_test: Import each module independently in Vitest's Node environment without rendering or invoking it.
fix_rationale: Defer the utility dependency until invocation and prevent Next from server-loading the rendered player.
blind_spots: Other packages may wrap lottie-web outside the two currently identified imports.
candidate_causes:
code: eager lottie-web imports in both the upload utility and react-lottie-player wrapper
config: Next 14.2.35 page-data collection evaluates the Pages Router import graph
environment: Node has no document global
data: none; failure occurs without request data
and_gate: yes; fixing either eager path alone leaves the other route-import path able to crash page-data collection
tdd_checkpoint:
test_file: apps/web/utils/getLottieThumbnailAndDuration.test.ts
test_name: can load the upload utility without a DOM
status: green; both Node import regressions and the held-out production build pass

## Symptoms

expected: `pnpm --filter @campsite/web build` completes without provider credentials or outbound release publication.
actual: Compilation and type checking pass, then page-data collection fails for `/[org]/chat/new`.
errors: `ReferenceError: document is not defined` from `lottie-web/build/player/lottie_light.js:createTag`.
reproduction: `mise exec -- env -u SENTRY_AUTH_TOKEN -u SENTRY_ORG -u SENTRY_PROJECT NEXT_TELEMETRY_DISABLED=1 pnpm --filter @campsite/web build`
started: First confirmed after upgrading the lockfile from Next 14.2.5 to 14.2.35; prior build status is unavailable.

## Eliminated

- hypothesis: Sentry source-map upload causes the page-data crash
  evidence: The build has no Sentry auth token and explicitly reports that release/source-map upload is disabled before reaching the local ReferenceError.
  timestamp: 2026-08-11T16:08:00+05:45

## Evidence

- timestamp: 2026-08-11T16:08:00+05:45
  checked: Attached production build with telemetry and Sentry credentials disabled
  found: Deterministic ReferenceError while collecting `/[org]/chat/new` page data
  implication: This is a local SSR import failure, not a provider/network failure.
- timestamp: 2026-08-11T16:08:00+05:45
  checked: Direct imports of lottie-web in apps/web
  found: Only `utils/getLottieThumbnailAndDuration.ts` imports `lottie_light` directly at module scope
  implication: Deferring this one import should remove the server-evaluation side effect without deleting Lottie behavior.
- timestamp: 2026-08-11T16:10:00+05:45
  checked: Held-out build after deferring only the upload utility import
  found: The identical ReferenceError remained through react-lottie-player in `components/Lottie.tsx`
  implication: The failure has two independent eager import paths; both require isolation from SSR.
- timestamp: 2026-08-11T16:14:00+05:45
  checked: Two Node import tests and full Next 14.2.35 production build
  found: 2 tests pass; all 42 static pages generate; `/[org]/chat/new` succeeds; build exits 0
  implication: Both root causes are covered by focused and held-out signals.
- timestamp: 2026-08-11T23:22:29+05:45
  checked: Human verification checkpoint
  found: User explicitly confirmed the Lottie/Next build evidence and authorized the narrow packaging commit.
  implication: The debug session can move to resolved.

## Resolution

root_cause: Two modules in the chat attachment graph eagerly load DOM-only Lottie code: `getLottieThumbnailAndDuration.ts` imports lottie-web directly and `components/Lottie.tsx` imports react-lottie-player, which loads lottie-web transitively.
fix: Lazy-load lottie-web inside the browser-only upload function and load react-lottie-player through `next/dynamic` with SSR disabled.
verification:
target_test: { result: pass }
mutation_check: { result: skipped, reason_if_skipped: "Stryker is not configured for this workspace" }
no_op_deletion: { result: pass, deletion_justified_by_rca: true }
adjacent_tests: { result: pass, suites_run: ["two Node-environment Vitest import regressions", "full Next production build"] }
revert_and_reconfirm: { result: pass, bug_returned_on_revert: true, fixed_on_reapply: true }
guardrail_verdict: accepted
oracle_type: derived
files_changed:

- apps/web/utils/getLottieThumbnailAndDuration.ts
- apps/web/utils/getLottieThumbnailAndDuration.test.ts
- apps/web/components/Lottie.tsx
- apps/web/components/Lottie.test.tsx
