---
status: resolved
trigger: "After the Tailwind cutover, the sidebar Profile and settings tooltip wraps vertically and the online indicator is missing."
created: 2026-08-26
updated: 2026-08-26
---

## Symptoms

- Expected: the tooltip remains a compact single line and the avatar shows its green online indicator.
- Actual: the tooltip collapses into a narrow multi-line block and the online indicator is absent.
- Errors: none reported.
- Timeline: began after the Tailwind CSS v4 cutover.
- Reproduction: hover the profile avatar in the collapsed desktop sidebar on staging.

## Current Focus

- hypothesis: confirmed.
- test: production build, generated CSS inspection, homelab staging deploy, and authenticated Brave route checks.
- expecting: complete.
- next_action: user confirmation of the feedback success toast after the next real submission.

## Evidence

- timestamp: 2026-08-26
  observation: User-provided before/after screenshots show the tooltip width and online badge regressions on the same control.
- timestamp: 2026-08-26
  observation: Tailwind v4 compiled legacy max-w-sm as max-width: 2px because spacing.sm is 2px.
- timestamp: 2026-08-26
  observation: Bare arbitrary variables such as w-[--sidebar-width] compiled to invalid declarations such as width:--sidebar-width.
- timestamp: 2026-08-26
  observation: The two web images omitted the Pusher key and cluster build arguments, leaving the presence store disconnected.
- timestamp: 2026-08-26
  observation: apps/web and packages/ui resolved separate react-hot-toast versions, so producers and the rendered Toaster subscribed to different stores.
- timestamp: 2026-08-26
  observation: Generated CSS now contains width:var(--sidebar-width), max-width:var(--feed-width), and max-width:var(--post-width), with zero bare variable declarations.
- timestamp: 2026-08-26
  observation: App image 694cd6d is healthy on both homelab web services; authenticated Brave checks show restored projects/reader geometry, the presence badge, and a non-crashing emoji-pack empty state.

## Eliminated

## Resolution

- root_cause: Tailwind v4 changed arbitrary CSS-variable parsing and widened theme namespace collisions; the deploy also omitted presence build settings, and duplicate react-hot-toast versions split the toast store.
- fix: wrapped all arbitrary variables in var(...), replaced max-w-sm uses with the equivalent max-w-96 token, unified react-hot-toast through the workspace catalog, supplied Pusher build args, and guarded empty emoji packs.
- verification: 144 web tests passed; production-style web build passed; changed-file lint and formatting passed; both staging web services route image 694cd6d; authenticated projects and emoji settings routes were visually checked.
- files_changed: 50 source/config/lock/test files in commit 694cd6d; deploy timeout follow-up in 26410ac.
