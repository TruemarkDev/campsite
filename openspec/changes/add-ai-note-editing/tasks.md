# Tasks: add-ai-note-editing

## 1. Suggestion marks + resolution (packages/editor) — the core

- [x] 1.1 Implement `suggestionInsert` / `suggestionDelete` marks (attrs: actorId, actorType, invokedBy, batchId, createdAt), modeled on MIT tiptap-track-changes, integrated with our kits
- [x] 1.2 Implement `resolveSuggestions(doc, mode)` util + editor commands `acceptSuggestion(batchId)` / `rejectSuggestion(batchId)` / `acceptAllSuggestions()` / `rejectAllSuggestions()`, idempotent under double resolution
- [x] 1.3 Unit tests: apply/accept/reject round-trips, replacement batches (delete+insert pairing), concurrent double-resolution convergence (two Yjs clients), copy/paste behavior
- [x] 1.4 Bump `NOTE_SCHEMA_VERSION` for suggestion marks and verify the existing stale-client read-only flow; defer UniqueID to bead campsite-7j7 until the latest stable package clears supply-chain age policy

## 2. Derived-content safety

- [x] 2.1 Apply `resolveSuggestions(..., 'strip')` in sync-server's `Database.store` HTML generation so `description_html` never contains unresolved suggestions
- [x] 2.2 Audit + fix other renderers: styled-text-server conversions, `RichTextRenderer`, any search/preview text extraction
- [x] 2.3 Tests: doc with unresolved suggestions → stored HTML/Slack/plain-text shows accepted content only

## 3. Review UI (apps/web)

- [x] 3.1 Suggestion rendering styles (insert underline/tint, delete strikethrough, actor color + AI badge) in note editor CSS
- [x] 3.2 Inline resolution widget on suggestion hover/focus (reuse comment-popover pattern): accept / reject, actor + instruction shown
- [x] 3.3 Note-level summary pill ("N suggested changes") with accept-all / reject-all / step-through
- [x] 3.4 Activity/attribution: surface proposal + resolution events in note activity

## 4. Command surface: "Edit with AI"

- [x] 4.1 Rails `POST .../notes/:id/ai_edits` — instruction + serialized range/context → LLM → structured edit ops constrained to the range; authz mirrors note edit access; rate-limited
- [x] 4.2 Web: "Edit with AI" in `EditorBubbleMenu` (selection) and `/ai` slash command (cursor); pending state while ops arrive; apply ops as suggestion marks via 1.x commands
- [x] 4.3 E2E: select → instruct → suggestions appear → accept/reject; reject-all restores exact prior content; second collaborator sees and can resolve the same suggestions

## 5. Server-side application path (facade + agent auth)

- [x] 5.1 Spike `server.hocuspocus.openDirectConnection()`: apply a transaction to a live-viewed note and a closed note; verify store path; test awareness broadcast (fallback: internal provider client) — record outcome in design.md
- [x] 5.2 Rails `AgentSyncGrant` model + token issuance + verification endpoint; sync-server auth middleware; revocation via `onTokenSync` re-check
- [x] 5.3 Facade endpoints (`edit`, `stream`) with ops set_content/append_section/replace_section/stream, `mode: suggest|direct`, direct-with-active-editors refusal, markdown/HTML ingestion through editor kits, rate limits, attribution callback
- [x] 5.4 Integration tests: suggest-mode application lands resolvable suggestions; concurrent human+agent convergence; invalid content 422; revoked token mid-stream

## 6. Resolve call-recording pilot feasibility

- [x] 6.1 Feature flag `ai_note_editing`; Rails facade client
- [x] 6.2 Verify the target contract before wiring the job; document that `Call#summary` is not a collaborative `Note`, retain the HTML job, and prohibit implicit note creation or guessed ownership
- [x] 6.3 Run the existing call-summary job regression tests and defer a live-note E2E to a future call-to-note contract change
