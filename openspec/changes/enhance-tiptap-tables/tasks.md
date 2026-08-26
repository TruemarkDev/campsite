# Tasks: enhance-tiptap-tables

## 1. Confirm the implementation boundary

- [ ] 1.1 Inspect installed Tiptap table typings/runtime and record the exact supported commands and cell attributes (Inspection).
- [ ] 1.2 Confirm the existing table JSON/HTML fixtures, schema version behavior, and current dirty-work ownership before editing (Inspection).
- [ ] 1.3 Verify the policy exception is accepted before implementing user-facing behavior (Demonstration).

## 2. Expand table commands and menu

- [ ] 2.1 Add before/after row and column controls with truthful `editor.can()` state (Test).
- [ ] 2.2 Add merge/split controls and selection-sensitive disabled states (Test).
- [ ] 2.3 Add header-row/header-column toggles (Test).
- [ ] 2.4 Add alignment and background controls using existing UI primitives and design tokens (Test).
- [ ] 2.5 Preserve delete-table behavior and verify keyboard/focus/accessibility behavior (Demonstration).

## 3. Implement tabular paste

- [ ] 3.1 Add local TSV/CSV detection and a bounded parser covering quoted CSV fields, escaped quotes, commas in quotes, and line endings (Test).
- [ ] 3.2 Insert parsed cells from the active table cell without writing outside the table; define malformed/oversized-input fallback (Test).
- [ ] 3.3 Verify ordinary rich-text and plain-text paste behavior is unchanged outside tables (Test).

## 4. Validate persistence and consumers

- [ ] 4.1 Verify edited tables serialize to the existing JSON and semantic HTML renderer without schema/version changes (Test).
- [ ] 4.2 Verify reload persistence and two-client collaboration convergence for representative structural and paste operations (Test).
- [ ] 4.3 Run focused editor/web/table tests, relevant typecheck/lint, and `git diff --check` (Test).
- [ ] 4.4 Record any unsupported command, schema gap, accessibility issue, or policy/dependency blocker as an explicit follow-up issue (Inspection).
