# Design: enhance-tiptap-tables

## Context

- `packages/editor/src/extensions/Table.ts` re-exports Tiptap's existing `Table`, `TableCell`, `TableHeader`, and `TableRow` extensions.
- `apps/web/components/EditorBubbleMenu/EditorTableMenu.tsx` currently exposes add/delete row and column controls plus delete-table.
- Note content is synchronized through the existing Tiptap/ProseMirror/Yjs path. Table operations SHALL use editor transactions so they receive the same collaboration and undo behavior as current commands.
- `apps/web/components/RichTextRenderer/handlers/Table.tsx` already renders semantic HTML tables and reads column widths. This change does not redesign that renderer.
- The installed table extension already provides structural commands such as `addRowBefore`, `addRowAfter`, `addColumnBefore`, `addColumnAfter`, `mergeCells`, `splitCell`, `toggleHeaderRow`, `toggleHeaderColumn`, and `setCellAttr`/alignment support where enabled by the installed version. Exact command availability SHALL be confirmed against installed typings before implementation.

## Goals / Non-Goals

**Goals:**

- Make common table restructuring possible without leaving the note.
- Keep command enablement truthful for the current selection.
- Make formatting and paste behavior keyboard-accessible and collaborative.
- Preserve existing JSON/HTML contracts and avoid dependency additions.

**Non-Goals:**

- Spreadsheet semantics such as formulas, sorting, filtering, or calculated cells.
- A new table node schema or a second table implementation.
- Mobile-specific redesign beyond usable narrow-width overflow and accessible controls.

## Decisions

1. **Use native table commands first.** The menu SHALL call the installed Tiptap table commands through `editor.chain()` and `editor.can()`. Custom commands are permitted only for behavior absent from the installed extension.
2. **Keep table actions in the existing bubble menu.** Group controls by structure (rows/columns), cells (merge/split), headers, and presentation (alignment/background), while retaining the existing delete-table action.
3. **Use explicit labels and disabled states.** Every action SHALL have a visible tooltip/title and an accessible name. Unsupported actions SHALL be disabled rather than silently doing nothing.
4. **Use existing cell attributes.** Header state SHALL use `TableHeader`/the extension's header commands. Alignment and background SHALL use existing cell attributes and the current design-system color tokens. Do not introduce a new persisted attribute without proving that the installed schema lacks the required capability.
5. **Parse pasted data locally.** A paste is eligible when clipboard text contains tabs or multiple line-separated fields and the selection is inside a table. TSV is the default unambiguous format. CSV parsing SHALL support quoted fields, escaped quotes, commas inside quoted fields, and CRLF/LF line endings without adding a package.
6. **Bound paste to the table.** Pasted rows and columns SHALL populate from the active cell, never silently expand beyond the table. The UX SHALL make truncation or an unavailable paste target clear; it SHALL not overwrite content outside the selected table.
7. **Preserve collaboration semantics.** All structural, formatting, and paste changes SHALL be editor transactions through the existing collaboration provider. No REST overwrite or direct Yjs mutation is introduced.
8. **Schema/version outcome.** Native structure, headers, and alignment use the existing schema. Background color is not represented by the installed table extension, so the implementation adds a local `backgroundColor` cell attribute, updates the semantic renderer, and bumps `NOTE_SCHEMA_VERSION` from 9 to 10. This is the documented compatibility-impacting exception; no dependency is added.

## Risks / Trade-offs

- Native command availability can differ across the installed Tiptap version; typings and runtime tests must be the source of truth.
- Merge/split behavior is selection-sensitive and can be confusing if controls are enabled too broadly; command availability tests are required.
- Background colors can reduce contrast in dark mode; use approved tokens and test focus/selected/text contrast.
- CSV parsing is deceptively complex; the supported grammar must remain bounded and malformed input must fall back to normal paste rather than corrupting a table.
- Two collaborators applying structural operations concurrently may produce valid but surprising layouts; existing Yjs convergence and persistence tests should cover validity, while product-level conflict resolution remains out of scope.
