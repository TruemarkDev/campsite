# Proposal: enhance-tiptap-tables

## Why

Campsite notes already support collaborative Tiptap tables, but the current table bubble menu only adds or deletes rows and columns. Users cannot efficiently restructure a table, mark headers, format cell presentation, or bring tabular data into a note. These are high-value editor improvements identified in `titap-plan.md`, while the repository remains in stewardship mode and therefore requires an explicit policy exception before implementation.

## What Changes

- Expand the table bubble menu with insert-row/column-before and insert-row/column-after actions.
- Add merge-cell and split-cell actions where the current selection and table shape permit them.
- Add header-row and header-column toggles using the existing Tiptap table schema.
- Add cell alignment controls and a bounded set of cell background-color choices using existing editor/UI primitives.
- Support pasting rectangular TSV and CSV data into a table, preserving the existing table structure and using safe text parsing/escaping.
- Keep all edits in the existing ProseMirror/Yjs collaborative document so changes persist and converge across collaborators.
- Add focused unit/component, serialization, and collaboration coverage for enabled commands and paste behavior.
- Treat this as a policy exception proposal under `MAINTENANCE.md`; implementation SHALL add no new dependency.

## Non-Goals

- Version history, diff, or restore.
- Offline IndexedDB editing or crash recovery.
- Stable block IDs and block action menus.
- Find and replace.
- DOCX/PDF conversion, spreadsheet formulas, sorting, filtering, or a spreadsheet-like grid.
- Replacing the existing table renderer or changing the persisted note schema unless implementation evidence proves an unavoidable compatibility change.

## Capabilities

### New Capabilities

- `editor/table-editing`: comprehensive, collaborative table manipulation and tabular paste in notes.

### Modified Capabilities

<!-- none — this change adds a focused editor capability -->

## Impact

- `apps/web/components/EditorBubbleMenu/EditorTableMenu.tsx`: expanded commands, availability state, and accessible controls.
- `packages/editor`: only small local extensions/helpers if required to expose table commands or normalize paste; existing `@tiptap/extension-table` remains the source of table behavior.
- `apps/web` editor paste handling: TSV/CSV detection, parsing, and insertion within the active table.
- Existing table serializers/renderers and `NOTE_SCHEMA_VERSION`: unchanged unless a compatibility-impacting schema change is demonstrated and separately approved.
- Tests: table menu, editor command behavior, paste edge cases, HTML/JSON rendering, and two-client collaboration/persistence.

## Policy Exception

This proposal describes new user-facing behavior that is disallowed by the current stewardship policy. It is not implementation authorization. Work may begin only after the project owner accepts this OpenSpec (or updates the maintenance policy) and confirms the no-new-dependency constraint.
