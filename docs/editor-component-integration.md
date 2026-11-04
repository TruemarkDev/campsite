# Editor component integration checklist

Use this checklist whenever adding or changing a Tiptap node, mark, extension, node view, or editor UI control. An editor feature is complete only when every applicable consumer has an explicit contract. Supporting it in the editable note surface alone is not sufficient.

## 1. Define the contract first

Record these decisions in the implementation issue:

- Which schemas support the feature: note, Markdown/post/comment, chat, or a subset?
- Is it persisted document content, derived editor UI, or both?
- What should unsupported consumers do: preserve, render a fallback, or prevent insertion?
- What is the plain-text and Markdown representation?
- What happens in public/read-only, notification, Slack, export, search, and preview contexts?
- What are the keyboard, screen-reader, touch, narrow-screen, and reduced-motion behaviors?

Do not expose a slash command or toolbar action until its target schema and downstream consumers are ready.

## 2. Schema, persistence, and collaboration

- Add or configure the extension in the appropriate factory:
  - notes: `packages/editor/src/note.ts`
  - posts/comments and generic Markdown: `packages/editor/src/markdown.ts`
  - chat: `packages/editor/src/chat.ts`
- Export the extension and its public option types from `packages/editor/src/extensions/index.ts`.
- Follow the versioning rules beside `NOTE_SCHEMA_VERSION`. Adding an extension or changing persisted schema requires a version bump and mixed-client review.
- Verify HTML and JSON round trips preserve node attributes. For layout nodes, include widths, IDs, levels, and other structural metadata.
- Exercise the collaboration path in `apps/web/components/Post/Notes/useNoteEditor.tsx` with local and remote edits. Derived plugins must tolerate content arriving after editor creation.
- Confirm sync-server schema construction uses the same extension factory.

## 3. Editable web surfaces

- Implement insertion, selection, update, deletion, undo, redo, copy/paste, and cursor escape behavior.
- Decide whether the shared `MarkdownEditor` supports the feature. If it does, configure the same required safeguards there. If it does not, hide insertion UI and preserve existing content safely.
- Review slash commands, bubble menus, keyboard shortcuts, drag handles, file/drop handlers, and empty-document behavior.
- Give every icon-only or repeated control a unique accessible name. Tooltips are supplementary, not accessible names.
- Bound floating controls to the viewport. Provide a documented touch behavior when hover or drag interactions are unavailable.

## 4. Read-only and public rendering

- Add semantic handlers to `apps/web/components/RichTextRenderer` for every new persisted node type.
- Check all consumers, including public notes, posts, comments, calls, TLDR content, and message/thread bubbles.
- Add non-editor styles to `apps/web/styles/prose.css`; styles scoped to `.ProseMirror` do not cover public/read-only output.
- Use semantic HTML and test the resulting structure, accessible names, links, and responsive overflow.
- Derived editor UI that is not persisted, such as the current note table of contents, needs a separate public-product decision: omit it intentionally or build a heading-derived read-only equivalent.

## 5. Server and integration representations

- Update `api/lib/html_transform` so plain text and Markdown exports preserve meaningful content. Never add a content-bearing node to `HtmlTransform::Drop`.
- Test models and paths that consume transformed text: previews, notifications, search/indexing, exports, posts, comments, notes, calls, and messages.
- Update `apps/styled-text-server` for Markdown-to-HTML and HTML-to-Slack behavior. Slack has no native table block, so complex layouts need a readable textual fallback.
- Review email, Open Graph/image rendering, Figma/plugin consumers, API payloads, and any sanitizer allowlists.

## 6. Required test matrix

| Area            | Minimum evidence                                                         |
| --------------- | ------------------------------------------------------------------------ |
| Schema/parser   | HTML and Markdown parsing plus JSON/HTML attribute round trip            |
| Initial state   | Empty, feature-only, and feature-at-document-end documents               |
| Commands        | Insert, update, add/remove children where applicable, delete, undo/redo  |
| Cursor and drag | Before/inside/after navigation; move and copy semantics                  |
| Read-only       | Semantic renderer test and public consumer trace                         |
| Collaboration   | Local/remote edits and mixed schema-version behavior                     |
| Conversion      | Rails plain text/Markdown and styled-text HTML/Slack                     |
| Accessibility   | Unique names, keyboard operation, focus, and semantic structure          |
| Responsive      | Narrow viewport, horizontal overflow, touch/coarse pointer               |
| Regression      | Focused tests, lint, typecheck, relevant service suite, production build |

## 7. Release and UAT gate

- Run repository-pinned commands through `mise exec` where applicable.
- Keep snapshot changes intentional and review the semantic output before accepting them.
- Test editable and read-only flows in a real browser at desktop and mobile widths.
- Verify persisted content after reload and through a second collaborative client.
- Confirm public/share, export, Slack/notification, and copy/paste behavior.
- Capture any unsupported behavior as a Beads issue before declaring the component complete.

## Current examples

### Table

Tables are persisted nodes. They therefore require note and Markdown schema configuration, row/column commands, resizing, cursor escape, note block dragging, semantic read-only handlers, responsive styles, Rails plain-text/Markdown conversion, and a Slack-safe row fallback.

### Table of contents

The current note table of contents is derived UI produced from heading nodes; it is not persisted as a node. It must update after local and collaborative heading changes, handle duplicate or empty headings and stable anchors, provide keyboard-accessible navigation without hiding focused content, respect reduced motion, and have an explicit decision for public/read-only notes.
