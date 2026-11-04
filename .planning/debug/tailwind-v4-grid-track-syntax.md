---
status: resolved
trigger: "The current profile feed layout is distorted after the Tailwind CSS v4 upgrade; the pre-upgrade instance is correctly aligned."
created: 2026-08-26
updated: 2026-08-26
---

## Symptoms

- Expected: feed avatars and the post byline/content column use the fixed two-column layout shown by the pre-upgrade instance.
- Actual: avatars remain at the feed edge while each post's byline/content column begins at a different horizontal position.
- Errors: no runtime error is visible.
- Timeline: began after the Tailwind CSS v4 cutover.
- Reproduction: open a member profile with multiple feed posts in the upgraded private web instance.

## Current Focus

- hypothesis: confirmed.
- test: source guard test, focused lint and formatting, full web tests, and Tailwind v4 compilation of the web and site stylesheets.
- expecting: complete.
- next_action: build and deploy the Campsite web images when explicitly authorized, then visually confirm the authenticated profile feed.

## Evidence

- timestamp: 2026-08-26
  observation: The user-provided comparison shows matching page-shell and feed geometry but variable gaps between each feed avatar and its byline/content column.
- timestamp: 2026-08-26
  observation: The upgraded live image emits `grid-template-columns:52px,minmax(0,1fr)`, while the pre-upgrade image emits `grid-template-columns:52px minmax(0,1fr)`.
- timestamp: 2026-08-26
  observation: CSS Grid track lists are whitespace-separated; the upgraded declaration is discarded and the browser falls back to auto-sized implicit columns.
- timestamp: 2026-08-26
  observation: The same invalid top-level comma syntax affected call bubbles, search results, member selectors, emoji packs, call transcripts, and marketing-site grids.
- timestamp: 2026-08-26
  observation: Tailwind v4 now emits valid whitespace-separated column and row declarations for both the web and site stylesheets; the source guard reports no offenders.
- timestamp: 2026-08-26
  observation: Focused ESLint and Prettier checks pass under mise Node 24.19.0, and the complete web Vitest suite passes 155 tests across 34 files.

## Eliminated

- hypothesis: The whole application is rendered with a different browser zoom or missing spacing scale.
  reason: Both images retain the same fixed feed width, composer geometry, vertical rhythm, and core spacing utility values.
- hypothesis: The extra organization switcher rail is a Tailwind regression.
  reason: It reflects different workspace/account state and does not explain the post-local variable alignment.

## Resolution

- root_cause: Tailwind v3 treated top-level commas in arbitrary grid track values as spaces, while Tailwind v4 preserves them. Values such as `grid-cols-[52px,minmax(0,1fr)]` therefore compiled to invalid CSS and the browser auto-sized implicit grid tracks.
- fix: Replaced top-level commas with Tailwind arbitrary-value underscores across the affected web and marketing grids, while preserving commas inside functions such as `minmax()`. Added a repository-wide source guard for this syntax.
- verification: Both Tailwind v4 stylesheets compile with valid grid track lists; focused lint and formatting pass; all 155 web tests pass.
- files_changed: Nine source components plus `apps/web/__tests__/tailwind-grid-syntax.test.ts`.
