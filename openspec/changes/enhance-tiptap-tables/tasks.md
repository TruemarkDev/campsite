# Tasks: enhance-tiptap-tables

## 1. Confirm the implementation boundary

- [x] 1.1 Inspect installed Tiptap table typings/runtime and record the exact supported commands and cell attributes (Inspection).
- [x] 1.2 Confirm the existing table JSON/HTML fixtures, schema version behavior, and current dirty-work ownership before editing (Inspection).
- [x] 1.3 Verify the policy exception is accepted before implementing user-facing behavior (Demonstration).

## 2. Expand table commands and menu

- [x] 2.1 Add before/after row and column controls with truthful `editor.can()` state (Test).
- [x] 2.2 Add merge/split controls and selection-sensitive disabled states (Test).
- [x] 2.3 Add header-row/header-column toggles (Test).
- [x] 2.4 Add alignment and background controls using existing UI primitives and design tokens (Test).
- [x] 2.5 Preserve delete-table behavior and verify keyboard/focus/accessibility behavior (Demonstration).

## 3. Implement tabular paste

- [x] 3.1 Add local TSV/CSV detection and a bounded parser covering quoted CSV fields, escaped quotes, commas in quotes, and line endings (Test).
- [x] 3.2 Insert parsed cells from the active table cell without writing outside the table; define malformed/oversized-input fallback (Test).
- [x] 3.3 Verify ordinary rich-text and plain-text paste behavior is unchanged outside tables (Test).

## 4. Validate persistence and consumers

- [x] 4.1 Verify edited tables serialize to the existing JSON and semantic HTML renderer with the documented schema-version bump (Test).
- [ ] 4.2 Verify reload persistence and two-client collaboration convergence for representative structural and paste operations (Test).
- [x] 4.3 Run focused editor/web/table tests, relevant typecheck/lint, and `git diff --check` (Test).
- [x] 4.4 Record any unsupported command, schema gap, accessibility issue, or policy/dependency blocker as an explicit follow-up issue (Inspection).

## Implementation status

- The native table commands, menu controls, local TSV/CSV parser, bounded table paste transaction, background-color cell attribute, and renderer support are implemented.
- `NOTE_SCHEMA_VERSION` is 10 because background color is a new persisted cell attribute; the editor snapshots were updated accordingly.
- ⚠️ Interactive browser/mobile UAT and a live two-client collaboration pass remain open. The existing browser UAT bead `campsite-vqa.9` remains open.
