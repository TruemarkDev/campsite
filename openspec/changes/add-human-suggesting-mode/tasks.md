# Tasks: add-human-suggesting-mode

## 1. Lock the baseline and rollout contract

- [ ] 1.1 Add focused regression tests that capture the current human-attributed mark behavior, proposed-content leakage into committed projections, and accept-versus-reject collaboration gap before changing implementation. Verification: run the focused editor and sync-server tests and confirm each new test fails for only its intended missing contract.
- [ ] 1.2 Add a shared human-suggesting capability flag and compatibility handshake across Rails, web, and sync-server so the mode stays hidden unless all required services advertise support. Verification: exercise supported and mixed-version combinations and confirm mixed versions fail closed without mutating a note.
- [ ] 1.3 Confirm that the existing suggestion mark attributes can represent human batches without a schema change; if any persisted attribute changes, bump `NOTE_SCHEMA_VERSION` and extend stale-client protection. Verification: run schema compatibility tests covering a current client, a stale client, and a document containing unresolved human suggestions.

## 2. Build the durable Rails batch lifecycle

- [ ] 2.1 Add a durable `NoteSuggestionBatch` record for batch UUID, note, source, proposer, status, resolver, timestamps, and retryable application errors, with a unique note-and-batch constraint. Verification: run model tests for validation, duplicate registration, and concurrent creation.
- [ ] 2.2 Add editor-authorized registration endpoints and serializers for human suggestion batches; derive the proposer from the authenticated principal and ignore client-supplied actor identity. Verification: run controller and policy tests for editors, viewers, outsiders, duplicate requests, and spoofed attribution.
- [ ] 2.3 Implement an idempotent server-side resolution state machine whose first committed accept or reject wins, and enqueue sync application without recording final activity early. Verification: run model, controller, and job tests for accept, reject, opposing concurrent decisions, duplicate delivery, and retry after sync failure.
- [ ] 2.4 Route existing AI/agent suggestion batches through the same durable resolution lifecycle, with lazy registration for unresolved legacy batches. Verification: run existing AI-edit and agent-facade tests plus migration-path tests proving one proposal and one final resolution event per batch.
- [ ] 2.5 Regenerate the API contract and TypeScript client after controller or serializer changes. Verification: run `script/gen-client`, confirm generated output is stable on a second run, and run the affected web typecheck.

## 3. Make committed content and resolution authoritative

- [ ] 3.1 Replace the ambiguous `resolveSuggestions(..., 'strip')` behavior with explicit `review`, `committed`, and `proposed` projections; committed projection SHALL remove insertions and restore deletions until acceptance. Verification: run unit tests for human and AI insert, delete, and replacement batches in every projection.
- [ ] 3.2 Update sync-server persistence and every downstream content projection to use committed content, including stored HTML, search, notifications, Slack, exports, previews, thumbnails, public/share rendering, and plain text. Verification: run a consumer matrix with unresolved, accepted, and rejected batches and confirm only the expected committed text leaves the editor.
- [ ] 3.3 Add an authenticated sync-server facade operation that applies one Rails-approved resolution idempotently to both live and cold Yjs documents. Verification: run integration tests for live viewers, unopened notes, repeated requests, missing batches, and storage failure followed by retry.
- [ ] 3.4 Extend two-client collaboration coverage to opposing accept/reject races and delayed duplicate delivery. Verification: prove all clients, persisted Yjs state, Rails batch state, and derived HTML converge on the first server-committed decision.
- [ ] 3.5 Provide a dry-run and backfill path that regenerates affected committed projections without rewriting Yjs suggestion state. Verification: run it against fixtures containing unresolved legacy suggestions, inspect the report, and confirm a second run is a no-op.

## 4. Implement the first-party editor mode

- [ ] 4.1 Add a `HumanSuggesting` editor extension with local mode storage, commands, transaction metadata, and guards that transform only eligible local user input while leaving remote and system transactions untouched. Verification: run extension tests for local input, remote Yjs input, programmatic document replacement, and mode transitions.
- [ ] 4.2 Transform text insertion, deletion, replacement, selected-range Suggest edits, and plain-text paste into paired `suggestionInsert` and `suggestionDelete` marks with authenticated batch metadata. Verification: run round-trip tests proving accept yields the proposal and reject restores the exact prior document.
- [ ] 4.3 Implement deterministic batching boundaries and Yjs undo origins so contiguous typing groups sensibly, navigation or mode changes close a batch, and undo affects only the current user's unresolved input. Verification: run tests for typing, backspace, selection replacement, cursor movement, mode switching, remote edits, and resolved batches.
- [ ] 4.4 Fail closed for unsupported structural or formatting transactions, rich-content paste, block joins/splits, tables, attachments, drag/drop, and mixed text-plus-structure input. Verification: run command-level tests proving unsupported operations neither create partial batches nor silently apply direct edits.
- [ ] 4.5 Cover composition and text-boundary correctness for IME, grapheme clusters, bidirectional text, and CJK input. Verification: run focused editor tests that accept and reject each fixture without corrupting text or mark boundaries.

## 5. Add the web experience and permissions

- [ ] 5.1 Add an editor-only Editing/Suggesting control to each supported note editor, defaulting every newly mounted editor to Editing and displaying the active mode without relying on color alone. Verification: run component tests for role visibility, remount/reset behavior, keyboard operation, and accessible name/state.
- [ ] 5.2 Surface clear feedback when an unsupported command is blocked and offer an explicit plain-text paste choice for rich clipboard content. Verification: run component tests for toolbar, keyboard, paste, mobile, and cancellation flows with no unintended document mutation.
- [ ] 5.3 Register new batches durably, show pending/error state, and change review controls to request Rails resolution before applying the sync mutation; remove the current local-first resolution path. Verification: run web mutation tests for success, duplicate click, authorization loss, network failure, retry, and a competing collaborator decision.
- [ ] 5.4 Let viewers inspect suggestion styling and attribution while preventing mode activation, suggestion creation, and resolution. Verification: run policy-backed component and request tests for editor, viewer, outsider, and revoked access.
- [ ] 5.5 Render human proposal and resolution activity with actor, action, and timestamp while preserving existing AI attribution. Verification: run serializer and timeline tests and confirm duplicate retries do not create duplicate activity.

## 6. Validate and release safely

- [ ] 6.1 Run focused Rails, editor, web, sync-server, and styled-text-server test suites for all changed surfaces. Verification: record the exact commands and passing counts with no committed focus markers.
- [ ] 6.2 Run repository lint, formatting, typecheck, API generation, and build gates required by the touched packages. Verification: confirm clean command exits and inspect generated diffs before staging anything.
- [ ] 6.3 Run a two-browser Playwright scenario covering text insert/delete/replace, reload, undo, viewer inspection, opposing accept/reject, retry, and final convergence. Verification: retain the browser assertions and raw test result for the exact revision under test.
- [ ] 6.4 Complete the committed-content consumer matrix for public/share pages, search, Slack, notifications, exports, previews, thumbnails, stored HTML, and plain text. Verification: demonstrate that unresolved proposals never appear and that acceptance or rejection updates each surface once.
- [ ] 6.5 Complete keyboard-only, screen-reader, mobile viewport, IME, CJK, bidirectional-text, and reduced-motion acceptance checks. Verification: record each scenario as pass, partial, or failed without substituting source inspection for interaction evidence.
- [ ] 6.6 Exercise the feature flag and compatibility gate through enable, mixed-version refusal, disable, and rollback in a production-like environment; deploy to the declared homelab only with separate operator authorization. Verification: capture exact service revisions, health evidence, rollback result, and proof that disabling the flag leaves existing unresolved batches reviewable.
- [ ] 6.7 Re-run `openspec validate add-human-suggesting-mode --strict` after implementation updates the artifacts. Verification: the command exits successfully and every implemented deviation is reflected in the design, specification, or task status before archival.
