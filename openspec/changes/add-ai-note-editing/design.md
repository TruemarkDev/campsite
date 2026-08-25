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
- A schema-version bump covering suggestion marks; UniqueID follows in bead campsite-7j7 after its dependency clears supply-chain policy.

**Non-Goals:**

- Human-to-human suggesting mode UI (the marks support it; surfacing a "suggesting" toggle for humans is a follow-up change).
- Ghost-text autocomplete, chat sidebar, AI document Q&A.
- External integrations (Aegis et al.) — periodic report notes use existing REST/MCP `update_note`; nothing here targets them.
- Format-change suggestions (bold→plain etc.) in v1 — insertions/deletions/replacements only.

## Decisions

1. **Suggestion representation: two marks** — `suggestionInsert` and `suggestionDelete`, attrs `{ actorId, actorType: 'ai'|'user', invokedBy?, instruction?, batchId, createdAt }`. `instruction` is bounded by the AI endpoint and retained in collaborative state so every reviewer can see why the change was proposed; effective-content renderers strip all suggestion metadata. A replacement = delete-mark on old + insert-mark on new, sharing `batchId` so review UI treats it as one change. Marks (not nodes/decorations) because they sync via Yjs for free, survive copy/paste sensibly, and match the comment-mark precedent. Deleted-but-suggested text stays in the doc wearing `suggestionDelete` (struck through) until resolution — this is the track-changes model.
2. **"Effective content" definition**: accepted content = doc minus `suggestionDelete`-marked text, with `suggestionInsert` marks stripped. Server-side renderers (sync-server `generateHTML` store path, styled-text-server) MUST strip unresolved suggestions when producing `description_html`/exports — a shared `resolveSuggestions(doc, 'accept'|'reject'|'strip')` util in `packages/editor`. This keeps derived HTML (Slack, search, previews) showing only accepted content.
3. **Accept/reject as editor commands** in `packages/editor` (`acceptSuggestion(batchId)`, `rejectSuggestion(batchId)`, `acceptAllSuggestions()`, …) so web UI, facade, and tests share one implementation. Review UI: inline widget on hover/focus of a suggestion (reuse the comment-popover pattern) + a summary pill when a note has unresolved suggestions.
4. **Command surface**: "Edit with AI" button in `EditorBubbleMenu` (selection path) and a `/ai` slash command (cursor path). Both call a new Rails endpoint `POST .../notes/:id/ai_edits` with `{ instruction, range, context }`; Rails runs the LLM with note context and returns edit operations; the **client applies them as suggestion marks locally** (single-user path needs no facade round-trip — it's just editor transactions), synced to collaborators via the normal provider.
5. **Server-side application path (facade)** — retained from the original design for jobs and offline notes: colocated with sync-server, applies ops via `server.hocuspocus.openDirectConnection()` (fallback: internal `@hocuspocus/provider` client), operations `set_content` / `append_section` / `replace_section` / `stream`, each with `mode: 'suggest' | 'direct'`. `direct` refused when active human editors are present unless `force: true`. Content ingested as markdown/HTML through the `packages/editor` kits; parse failure → 422.
6. **Auth for the facade**: Rails-issued `AgentSyncGrant` (actor, note, scope, expiry) → opaque signed token → sync-server verifies via a Rails endpoint, mirroring the human token path; revocation enforced at `onTokenSync` re-check (composes with bead campsite-8ss). The user-invoked path needs none of this — it rides the user's own session.
7. **Schema-version strategy**: bump `NOTE_SCHEMA_VERSION` for `suggestionInsert`/`suggestionDelete` now, with the established stale-client read-only behavior. UniqueID (campsite-7j7) requires a later bump because installing an older package violates the latest-stable rule and the current latest release has not aged through `minimumReleaseAge`.
8. **Call-summary pilot removed**: `Call#summary` is a standalone HTML field assembled from `CallRecordingSummarySection` records, not a collaborative `Note`. The note-scoped facade SHALL NOT guess or create a target note. The existing summary job remains the as-built path until a separate change defines call-to-note ownership and lifecycle.

## Risks / Trade-offs

- **Suggestion marks in collab**: two humans resolving the same batch concurrently must converge — accept/reject commands are mark removals/text deletions, which Yjs merges, but double-resolution needs idempotent commands (no-op if batch already resolved). Covered in tests.
- **Derived-content leakage**: any renderer that forgets to strip unresolved suggestions leaks "deleted" text into Slack/search/HTML. Mitigation: `resolveSuggestions` lives in `packages/editor` and the store path applies it centrally in sync-server; audit styled-text-server and RichTextRenderer callers in tasks.
- **Marks vs. block-level suggestions**: mark model handles inline/text changes well but block operations (insert a whole section) become one large `suggestionInsert` span — acceptable for v1; block-granular UX can layer later.
- **LLM edit quality/scope creep**: the Rails endpoint constrains the model to the provided range and returns structured ops (not raw doc rewrites); reject-all is always one click.
- **`openDirectConnection` awareness semantics** unverified for the streaming pilot — spike first; provider-client fallback documented (decision 5).
- **Schema bump blast radius**: deferring UniqueID means a later read-only migration event, but preserves the repository's latest-stable and minimum-release-age policies.

## Implementation status (2026-08-25)

- The suggestion mark schema, resolution commands, effective-content transformer, sync-server store boundary, read-only renderer, Slack conversion, and base editor styling are implemented. `NOTE_SCHEMA_VERSION` is 9 so clients on version 8 become read-only before writing documents containing the new marks.
- ⚠️ **UniqueID is intentionally deferred.** The registry's latest stable `@tiptap/extension-unique-id` is 3.30.3, published 2026-08-24, and it requires exact 3.30.3 peers. Campsite deliberately pins the complete Tiptap/Hocuspocus editor graph to 3.29.2 and enforces a seven-day minimum release age. Installing 3.29.2 would violate the user-level latest-stable rule; installing 3.30.3 today would bypass the supply-chain age policy and require a graph-wide compatibility migration. `campsite-7j7` owns adoption after the package ages into policy and the full editor/sync graph passes compatibility tests.
- `openDirectConnection()` is viable for the facade. A direct connection loads a cold document through normal hooks, shares the same in-memory `Document` when a viewer is connected, broadcasts its Yjs transaction, and `disconnect()` defaults to an immediate durable store. Awareness updates placed on the shared document also broadcast, but the API does not allocate an isolated awareness client for a direct connection. The facade SHALL therefore create and remove a synthetic per-operation awareness client instead of using `document.awareness.setLocalState`, whose single server-local client ID would collide across concurrent agents.
- The note-scoped `AgentSyncGrant` path and sync-server facade are implemented. Grants are opaque, expiring, revocable, and rechecked during token sync. The facade supports `set_content`, `append_section`, `replace_section`, and streamed chunks in suggestion or direct mode; direct edits refuse active human collaborators unless explicitly forced. Proposal and resolution events are attributed in the note timeline.
- ❌ **The call-summary pilot is removed from this change.** `GenerateCallRecordingSummarySectionJob` writes HTML into a `CallRecordingSummarySection`; neither `Call` nor `CallRecording` belongs to a collaborative `Note`, and there is no call-to-note association from which to mint a note-scoped grant. Guessing or creating a note would change product behavior and data ownership. The existing HTML summary path remains the as-built implementation and its regression tests remain green.
- Browser acceptance is complete. Playwright creates a note, selects text, invokes the AI edit UI with a controlled endpoint response, observes the same attributed suggestion in a second live Hocuspocus client, rejects it there, and verifies both clients converge to the exact original content.
