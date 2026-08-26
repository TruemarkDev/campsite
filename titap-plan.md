• Campsite already has a strong baseline: collaboration, comments, AI suggestions, tables, TOC, attachments,
  references, toggles, and block dragging are wired into the /Users/prakash/workspaces/2025/campsite/packages/editor/
  src/note.ts:77 and /Users/prakash/workspaces/2025/campsite/apps/web/components/Post/Notes/useNoteEditor.tsx:52.

  My highest-value additions would be:

   Priority    Feature                                     Why it matters                                  Effort
  ━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━
   1           Version history with diff and restore       Collaborative and AI-assisted documents need    High
                                                           a reliable “who changed what?” and recovery
                                                           path. Tiptap supports named snapshots,
                                                           comparisons, and restores, but its official
                                                           implementation is Pro and expects its
                                                           collaboration provider, so it is not a drop-
                                                           in for Campsite’s self-hosted Hocuspocus
                                                           setup. Tiptap snapshots (https://tiptap.dev/
                                                           docs/collaboration/documents/snapshot)
  ──────────  ──────────────────────────────────────────  ──────────────────────────────────────────────  ────────────
   2           Offline editing and crash recovery          Persist the Yjs document in IndexedDB so        Medium
                                                           edits survive disconnects, tab closes, and
                                                           temporary sync outages, then merge when
                                                           connectivity returns. The key assumption to
                                                           validate is whether browser-local document
                                                           storage meets Campsite’s privacy/logout
                                                           requirements. Tiptap offline support
                                                           (https://tiptap.dev/docs/guides/offline-
                                                           support)
  ──────────  ──────────────────────────────────────────  ──────────────────────────────────────────────  ────────────
   3           Stable block links and block action menu    Give every block a durable ID, then add         Medium
                                                           “Copy link,” “Duplicate,” “Delete,”
                                                           “Comment,” and “Transform into…” beside the
                                                           existing drag handle. Tiptap’s UniqueID
                                                           survives splits, merges, paste, and undo/
                                                           redo. UniqueID extension (https://
                                                           tiptap.dev/docs/editor/extensions/
                                                           functionality/uniqueid)
  ──────────  ──────────────────────────────────────────  ──────────────────────────────────────────────  ────────────
   4           Full table editing                          The current /Users/prakash/workspaces/2025/     Low–Medium
                                                           campsite/apps/web/components/
                                                           EditorBubbleMenu/EditorTableMenu.tsx:14 only
                                                           adds/deletes rows and columns. Add before/
                                                           after placement, merge/split cells, toggle
                                                           header row/column, cell alignment/
                                                           background, and paste from TSV/CSV. Most
                                                           commands already exist in the installed
                                                           table extension. Tiptap table commands
                                                           (https://tiptap.dev/docs/editor/extensions/
                                                           nodes/table)
  ──────────  ──────────────────────────────────────────  ──────────────────────────────────────────────  ────────────
   5           Find and replace                            Essential once notes become long: next/         Low–Medium
                                                           previous result, case sensitivity, whole-
                                                           word matching, and replace-all. Tiptap now
                                                           provides an official extension and UI
                                                           pattern. Find and Replace (https://
                                                           tiptap.dev/docs/ui-components/components/
                                                           search-and-replace)

  Strong next-tier candidates:

  - Human “Suggesting” mode: extend Campsite’s existing
    /Users/prakash/workspaces/2025/campsite/apps/web/components/Post/Notes/SuggestionReview.tsx:75 to edits made by
    teammates. Excellent fit for async review, but Tiptap’s official Tracked Changes product is currently a paid
    alpha. Tracked Changes (https://tiptap.dev/docs/tracked-changes/getting-started/overview)

  - DOCX import and DOCX/PDF/Markdown export: valuable for onboarding and data portability, but Tiptap Conversion is
    Pro/Beta and some formats use its conversion service—important for homelab data custody. Conversion overview
    (https://tiptap.dev/docs/conversion/getting-started/overview)

  - Highlight, superscript, subscript, and text alignment: useful formatting polish, but less valuable than
    collaboration safety and navigation.

  - Math/LaTeX blocks: worthwhile if technical, research, or education teams are a target segment; it requires KaTeX
    and full renderer/export support. Mathematics extension
    (https://tiptap.dev/docs/editor/extensions/nodes/mathematics)

  - Word count and reading time: inexpensive and useful for long notes. Character Count
    (https://tiptap.dev/docs/editor/extensions/functionality/character-count)

  - Pagination, columns, and print layout: only pursue if Campsite is intentionally moving toward Google Docs/Word-
    style authoring.

  I would avoid prioritizing Tiptap’s drag-handle, file-handler, or emoji extensions: Campsite already has custom
  equivalents. My practical build order would be table power tools → find/replace → block links → offline recovery →
  version history.

  These remain proposal candidates: the current /Users/prakash/workspaces/2025/campsite/MAINTENANCE.md:12 prohibits
  new features and dependencies, so implementation would require an explicit policy exception/OpenSpec change.
