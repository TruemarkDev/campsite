# Editor roadmap notes — Tiptap 3 era and the 2026 landscape

Research captured 2026-08-12, after the Tiptap 2→3 / Hocuspocus 2→4 migration. This is a
reference document, not a commitment. Near-term, well-scoped work is tracked as beads
(label `tiptap3`); AI editing has an OpenSpec change
(`openspec/changes/add-ai-note-editing`). Everything else lives here so the research
doesn't have to be redone at implementation time.

## Where we are

- Tiptap `^3.29.2` everywhere (3.30.0 blocked only by the pnpm `minimumReleaseAge`
  supply-chain policy at time of writing — bump when it ages out, and drop the temporary
  `terser`/`electron-to-chromium` overrides in `pnpm-workspace.yaml` at the same time).
- Hocuspocus `^4.6.0`, self-hosted (`apps/sync-server`). Typed `Server<Context>`.
- Tables (`TableKit`) and Table of Contents integrated in notes.
- Pro registry fully removed; every extension we use is MIT.

## Tracked work (beads, label `tiptap3` unless noted)

| Bead | What |
|---|---|
| campsite-ahb | Selection extension — keep selection highlighted during comment flow |
| campsite-k78 | EditorBubbleMenu → `useEditorState` (kill rerender-per-transaction) |
| campsite-7j7 | UniqueID for stable block IDs (needs `NOTE_SCHEMA_VERSION` bump) |
| campsite-rff | Mathematics (LaTeX) — product call |
| campsite-auf | FileHandler vs custom paste/drop plumbing |
| campsite-dom | styled-text-server: markdown output via `@tiptap/markdown` |
| campsite-4oi | `@tiptap/static-renderer`: DOM-free JSON→HTML (blocks pua, s5r) |
| campsite-pua | html_to_slack as ProseMirror serialization (replaces cheerio) |
| campsite-s5r | PM JSON as first-class interchange + structural sanitization |
| campsite-l5e | Semantic diff endpoint via vendored recreate-transform |
| campsite-8ss | Hocuspocus 4 `onTokenSync` re-authorization (label `hocuspocus`) |

Full integration details (package versions, file paths, gotchas) are in each bead's
description — `bd show <id>`.

## The 2026 landscape — beyond the tracked work

The scene's defining shift in 2026: **the editor is a surface humans and AI agents
share**. Tiptap's business is now its Cloud (AI Toolkit, conversion, snapshots,
comments); its 2026 mission is "the document layer around the database" — schema-validated,
versioned, queryable docs. Because Campsite self-hosts the entire collab stack
(Hocuspocus + Yjs + own schema), every one of these has a viable OSS/DIY path.

### 1. User-invoked AI editing with suggestion review  → OpenSpec: `add-ai-note-editing`

**The proven shape** (Tiptap AI Toolkit "Cursor-like agent", Harvey/Spellbook legal
redlining, Rezonant docs): the user, *in* the note, selects text or types a command; AI
edits land **as suggestions** — attributed insert/delete marks, individually
accept/rejectable, Google-Docs style. The review workflow is the value; agent
connectivity is plumbing beneath it. MIT reference for the marks:
[`tiptap-track-changes`](https://github.com/sungkhum/tiptap-track-changes/); Tiptap's own
version is Cloud-paid.

The OpenSpec change covers: suggestion marks + accept/reject (core,
`NOTE_SCHEMA_VERSION` bump batched with UniqueID campsite-7j7), "Edit with AI"
bubble-menu/slash-command surface, a server-side edit facade for jobs, and one genuinely
*live* pilot — the call-recording summary streaming into the meeting note while
participants still have it open. Human-to-human suggesting mode is a natural follow-up
on the same marks.

**Explicitly not the pitch**: autonomous background writers maintaining status
documents. A periodic report note needs the existing REST/MCP `update_note`, not CRDT
streaming (see Aegis note below).

### 2. Inline AI autocomplete (ghost text)

Copilot-style grey completion text, Tab to accept. Tiptap's version is paid; the DIY
pattern is a ProseMirror decoration widget + debounced calls to our own LLM endpoint.
Product-sensitive in a communication tool — prototype behind
`useCurrentUserOrOrganizationHasFeature` if at all.

### 3. Version history with visual diff

Tiptap sells this as Snapshots (Cloud). We already store every ingredient: per-note Yjs
states (`description_state` in the API) and the vendored
`packages/editor/src/lib/recreate-transform`. Server half is bead campsite-l5e (diff
endpoint). The missing piece is UI: a versions panel rendering insert/delete decorations
between two states. For a team-memory product, "what changed since I last read this" is
a retention feature.

### 4. DOCX / PDF conversion

Tiptap's 2026 conversion push (DOCX round-trip, Word redlines, PDF) is Cloud-paid. Our
actual needs are narrower and fit styled-text-server as endpoints:

- Import: `mammoth` (MIT) for docx→HTML, then through our schema (which structurally
  sanitizes — only schema-known nodes survive).
- Export: pandoc or Typst in the styled-text-server container for note→PDF/DOCX.

Aligns with the "styled-text-server owns the schema; every format is a projection"
direction (beads campsite-4oi / s5r).

## Aegis note (deliberately demoted)

Aegis (Truemark's repo/PR quality platform, `~/workspaces/2026/aegis`) emitting per-repo
quality reports into Campsite is a fine idea — but it does **not** need any of the
agent-peer machinery. A report that updates a few times a day is a cron job hitting the
existing Campsite MCP/REST (`update_note`); a streaming caret on a status document is
theater. If Aegis integration happens, it is ordinary API consumption plus, at most, an
integration-scoped grant — track it in the Aegis repo, not here. (Earlier drafts of the
`add-ai-note-editing` OpenSpec change framed Aegis as a first consumer; that framing was
dropped on review — see the change's proposal for the current scope.)

## Sources

- [Tiptap 2026 roadmap](https://tiptap.dev/blog/release-notes/our-roadmap-for-2026)
- [Tiptap Q1 2026 recap — Server AI Toolkit](https://tiptap.dev/blog/release-notes/recap-q1-2026)
- [AI agents as CRDT peers with Yjs](https://electric.ax/blog/2026/04/08/ai-agents-as-crdt-peers-with-yjs)
- [tiptap-track-changes (MIT)](https://github.com/sungkhum/tiptap-track-changes/)
- [Tiptap pricing](https://tiptap.dev/pricing) · [What's new](https://tiptap.dev/docs/resources/whats-new)
