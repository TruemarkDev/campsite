---
status: resolved
trigger: "Collaborative notes worked well in January; after upgrading Tiptap and adding tables, two-person editing or table-containing notes intermittently duplicate the full document. Find the actual regression and implement a production-grade solution, not a homelab or single-user workaround."
created: 2026-08-26
updated: 2026-08-26
---

## Symptoms

- Expected: multiple collaborators and table-containing notes converge without duplicating any content.
- Actual: the supplied staging note persisted its complete content twice, including its table and attachment.
- Errors: no user-facing error accompanies the duplication; transient WebSocket warnings appear during provider connection replacement.
- Timeline: collaboration worked in January; flakiness began after the Tiptap/Hocuspocus upgrades and table integration in August.
- Reproduction: intermittent when two people edit the same note and/or the note contains a table; supplied note `u9gn7tgwsz2g` is a persisted example.

## Current Focus

- hypothesis: the August provider migration made connections a render-time side effect while the new table/TOC extensions can mutate a collaborative document before its first authoritative server sync. The existing HTML-to-Yjs fallback and last-writer-wins persistence then allow two independently generated roots to meet and persist as a duplicate.
- test: reproduce the full sequence with React Strict Mode, two clients, a table/heading document, reconnects, and independent server loads.
- expecting: no leaked provider, no document mutation before `onSynced`, and one Yjs lineage even when two clients connect together.
- next_action: add regression tests, make provider connection effect-owned, make the server document authoritative on initial sync, and remove non-atomic HTML-to-Yjs regeneration paths.

## Evidence

- timestamp: 2026-08-26
  observation: The note API persists two complete HTML copies with distinct heading IDs; this is not a renderer-only duplication.
- timestamp: 2026-08-26
  observation: Decoded Yjs state has 44 top-level nodes: two identical 22-node branches from two distinct Yjs client IDs, each with 155 structs and 283 clocks, plus a small heading metadata update.
- timestamp: 2026-08-26
  observation: Merging two independently generated `TiptapTransformer.toYdoc` results reproduces whole-document duplication, including tables.
- timestamp: 2026-08-26
  observation: The affected state was stored at schema version 9, before the latest schema-10 table enhancements.
- timestamp: 2026-08-26
  observation: Commit `db77773` replaced Hocuspocus v2 `connect: isLoggedIn` with an auto-connecting constructor followed by `disconnect()`. Hocuspocus v4 actually provides `autoConnect: false`; the current hook therefore starts network work during a React Strict Mode state initializer and only disconnects cleanup when the socket is already fully connected.
- timestamp: 2026-08-26
  observation: `apps/web/next.config.js` enables React Strict Mode. A discarded initializer-created provider can remain in `connecting` state and reconnect without an owning component; the supplied incident logs show the corresponding failed connection followed by two authenticated connections.
- timestamp: 2026-08-26
  observation: Tiptap TableOfContents assigns random heading IDs and dispatches a transaction in `onCreate`; `TrailingParagraphAfterTable` also dispatches in `onCreate` when a table is last. Neither is gated on Hocuspocus `onSynced`.
- timestamp: 2026-08-26
  observation: The sync server reconstructs a new Yjs document from HTML whenever `description_state` is null, while `UpdateMentionUsernamesJob` deliberately updates note HTML and clears `description_state`. This violates the one-lineage persistence invariant and makes a later merge of an old client state duplicate the document.
- timestamp: 2026-08-26
  observation: Worker logs contain no `UpdateMentionUsernamesJob` at the supplied note's 03:49 corruption window, so that job is a confirmed systemic hazard but not the immediate trigger for this example.

## Eliminated

- hypothesis: the read-only renderer duplicated one DOM subtree.
  reason: both `description_html` and binary `description_state` already contain two copies.
- hypothesis: the table extension duplicated only the selected table.
  reason: every node before and after the table, including the attachment, is duplicated as a complete snapshot.
- hypothesis: two reconnects of the same persisted Yjs update duplicate content by themselves.
  reason: Yjs updates from the same lineage are idempotent; duplication requires independently allocated structs, exactly as found in the affected state.

## Resolution

- root_cause: The Tiptap/Hocuspocus upgrade made provider construction auto-connect inside a React Strict Mode initializer, allowing discarded providers to survive. Clients also preloaded REST Yjs snapshots while the sync server independently regenerated missing state from HTML. Table/TOC initialization then supplied immediate document transactions. When two independently allocated roots met, Yjs correctly retained both complete documents.
- fix: Providers are now created with `autoConnect: false`, connected only from the authenticated effect, and disconnected even while connecting. Collaborative editors remain non-mutating until the first authoritative server sync and no longer seed provider documents from REST state. Legacy HTML conversion is persisted through an API row lock with initialize-once semantics, and losing cold loaders use the winning canonical binary state.
- verification: Web provider/Strict Mode tests pass; the real transformer two-loader regression keeps one heading, table, attachment, and paragraph; all 39 sync-server tests pass; 8 focused web table/TOC/provider tests pass; 28 Rails sync controller tests pass with 89 assertions; web TypeScript, sync build, Prettier, RuboCop, and diff checks pass. Sync-server standalone TypeScript remains blocked by the pre-existing `facade.ts:214` YXmlHook type error.
- files_changed: api sync-state controllers/tests, sync-server database/tests, web provider/editor/tests, and generated API types.
