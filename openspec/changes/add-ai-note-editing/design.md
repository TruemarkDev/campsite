# Design: add-ai-note-editing

## Context

- Sync stack: `apps/sync-server` on Hocuspocus **4.6** (`Server<Context>`); Rails fronts auth (`postMeSyncToken` → `onAuthenticate` → `getNotesSyncState`), `Database` extension round-trips `description_state` + `description_html` via `TiptapTransformer`. Schema comes from `packages/editor` `getNoteExtensions()`; `NOTE_SCHEMA_VERSION` gates stale clients read-only.
- Web: `EditorBubbleMenu` (selection menu, Floating UI, v3), `SlashCommand.tsx` (existing slash-command infra in `apps/web/components/Post/Notes/`), `CollaborationCaret` with custom awareness fields (`customColor`, `customSelection`) — precedent for an `isAgent` field. Comments are an existing **mark** with hover/activate callbacks — precedent for mark-based inline UI.
- Rails already runs LLM jobs (`generate_post_tldr_job`, `generate_call_recording_summary_section_job`, resolutions) and has the OpenAI/Anthropic plumbing; there is no user-invoked "edit this text" endpoint yet.
- Reference implementation for suggestion marks: MIT [`tiptap-track-changes`](https://github.com/sungkhum/tiptap-track-changes/) — insertions/deletions/format changes as inline marks with accept/reject. We implement our own extensions in `packages/editor` using its model (marks, not a parallel doc), adapted to our schema and collab setup.
- Prior art for the overall UX: Tiptap AI Toolkit ("Cursor-like agent", suggestion review, schema-aware edits) — paid; we build the equivalent on our stack. Research: `EDITOR_ROADMAP.md`.

## Goals / Non-Goals

**Goals:**
- "Edit with AI" on a selection or at the cursor, with every AI change reviewable (accept/reject per change + bulk) before it becomes real content.
- Suggestion marks that are collab-safe (Yjs-synced like any mark) and survive reload.
- One server-side edit path (facade) usable by the Rails AI endpoint and jobs; suggestion-mode or direct application.
- One schema-version bump covering suggestion marks (batched with UniqueID, bead campsite-7j7).

**Non-Goals:**
- Human-to-human suggesting mode UI (the marks support it; surfacing a "suggesting" toggle for humans is a follow-up change).
- Ghost-text autocomplete, chat sidebar, AI document Q&A.
- External integrations (Aegis et al.) — periodic report notes use existing REST/MCP `update_note`; nothing here targets them.
- Format-change suggestions (bold→plain etc.) in v1 — insertions/deletions/replacements only.

## Decisions

1. **Suggestion representation: two marks** — `suggestionInsert` and `suggestionDelete`, attrs `{ actorId, actorType: 'ai'|'user', invokedBy?, batchId, createdAt }`. A replacement = delete-mark on old + insert-mark on new, sharing `batchId` so review UI treats it as one change. Marks (not nodes/decorations) because they sync via Yjs for free, survive copy/paste sensibly, and match the comment-mark precedent. Deleted-but-suggested text stays in the doc wearing `suggestionDelete` (struck through) until resolution — this is the track-changes model.
2. **"Effective content" definition**: accepted content = doc minus `suggestionDelete`-marked text, with `suggestionInsert` marks stripped. Server-side renderers (sync-server `generateHTML` store path, styled-text-server) MUST strip unresolved suggestions when producing `description_html`/exports — a shared `resolveSuggestions(doc, 'accept'|'reject'|'strip')` util in `packages/editor`. This keeps derived HTML (Slack, search, previews) showing only accepted content.
3. **Accept/reject as editor commands** in `packages/editor` (`acceptSuggestion(batchId)`, `rejectSuggestion(batchId)`, `acceptAllSuggestions()`, …) so web UI, facade, and tests share one implementation. Review UI: inline widget on hover/focus of a suggestion (reuse the comment-popover pattern) + a summary pill when a note has unresolved suggestions.
4. **Command surface**: "Edit with AI" button in `EditorBubbleMenu` (selection path) and a `/ai` slash command (cursor path). Both call a new Rails endpoint `POST .../notes/:id/ai_edits` with `{ instruction, range, context }`; Rails runs the LLM with note context and returns edit operations; the **client applies them as suggestion marks locally** (single-user path needs no facade round-trip — it's just editor transactions), synced to collaborators via the normal provider.
5. **Server-side application path (facade)** — retained from the original design for jobs and offline notes: colocated with sync-server, applies ops via `server.hocuspocus.openDirectConnection()` (fallback: internal `@hocuspocus/provider` client), operations `set_content` / `append_section` / `replace_section` / `stream`, each with `mode: 'suggest' | 'direct'`. `direct` refused when active human editors are present unless `force: true`. Content ingested as markdown/HTML through the `packages/editor` kits; parse failure → 422.
6. **Auth for the facade**: Rails-issued `AgentSyncGrant` (actor, note, scope, expiry) → opaque signed token → sync-server verifies via a Rails endpoint, mirroring the human token path; revocation enforced at `onTokenSync` re-check (composes with bead campsite-8ss). The user-invoked path needs none of this — it rides the user's own session.
7. **Schema-version strategy**: one bump introducing `suggestionInsert`/`suggestionDelete` **and** UniqueID attrs (campsite-7j7) together. Follows the established rollout: bump `NOTE_SCHEMA_VERSION`, stale clients read-only via existing mechanism.
8. **Pilot** (`generate_call_recording_summary_section_job`): streams via facade with `mode: 'suggest'` when the note has active viewers (summary arrives as a reviewable block while the meeting doc is open), `mode: 'direct'` when nobody is watching. Feature-flagged; HTML path retained as fallback.

## Risks / Trade-offs

- **Suggestion marks in collab**: two humans resolving the same batch concurrently must converge — accept/reject commands are mark removals/text deletions, which Yjs merges, but double-resolution needs idempotent commands (no-op if batch already resolved). Covered in tests.
- **Derived-content leakage**: any renderer that forgets to strip unresolved suggestions leaks "deleted" text into Slack/search/HTML. Mitigation: `resolveSuggestions` lives in `packages/editor` and the store path applies it centrally in sync-server; audit styled-text-server and RichTextRenderer callers in tasks.
- **Marks vs. block-level suggestions**: mark model handles inline/text changes well but block operations (insert a whole section) become one large `suggestionInsert` span — acceptable for v1; block-granular UX can layer later.
- **LLM edit quality/scope creep**: the Rails endpoint constrains the model to the provided range and returns structured ops (not raw doc rewrites); reject-all is always one click.
- **`openDirectConnection` awareness semantics** unverified for the streaming pilot — spike first; provider-client fallback documented (decision 5).
- **Schema bump blast radius**: bundling with UniqueID doubles the payload of one bump but halves the number of read-only migration events — deliberate.
