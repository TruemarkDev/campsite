# Proposal: add-ai-note-editing

## Why

The proven, revenue-earning shape of AI in editors (Tiptap AI Toolkit, Harvey/Spellbook redlining, Rezonant docs) is not an autonomous background writer — it is **user-invoked, in-document editing with reviewable changes**: select text or type a command in the note you're editing, the AI proposes edits *in place*, and you accept or reject each change without leaving the document. Campsite has the LLM plumbing (Rails AI jobs) and the entire self-hosted collab stack, but no way for AI output to land in a note as anything other than a static, take-it-or-leave-it block. The review workflow — suggestion marks, accept/reject — is the value; agent connectivity is plumbing beneath it.

## What Changes

- **Suggestion-mode marks in the note schema** (core, **BREAKING** for persisted docs): insertion/deletion suggestion marks carrying actor attribution, individually accept/rejectable, collab-safe. Modeled on the MIT `tiptap-track-changes` approach, implemented as `packages/editor` extensions. Requires a `NOTE_SCHEMA_VERSION` bump (batch with UniqueID, bead campsite-7j7, to pay the deploy cost once).
- **Accept/reject review UI** in `apps/web`: per-suggestion inline controls + a review summary affordance ("N suggested changes — accept all / review"). Suggestions render distinctly (authorship color + agent badge).
- **Command surface**: "Edit with AI" from the selection bubble menu and a slash-command — instruction goes to a Rails AI endpoint with the selected range/note context; the response is applied as suggestions, never direct writes, when a human is present.
- **Agent edit infrastructure** (retained from the original framing, now explicitly subordinate): scoped agent auth (Rails-issued grants) and a server-side edit facade colocated with the sync-server, so producers apply schema-valid edits through the live collaborative session. This is what makes AI edits land in an open note in real time instead of via stale-write REST.
- **Pilot for live streaming** (the one case where liveness is the point): `generate_call_recording_summary_section_job` streams the summary into the meeting note while participants still have it open — as suggestions when viewers are present, direct write otherwise.
- **Dropped from scope**: Aegis/external-integration narrative. Periodic report notes need only the existing REST/MCP `update_note` path; no CRDT streaming, no special surface. External producer grants remain possible via the same auth model but are not a goal of this change.
- Not in scope: ghost-text autocomplete, chat sidebar, AI reads/analysis endpoints, any Tiptap Cloud service.

## Capabilities

### New Capabilities
- `editor/ai-note-editing`: user-invoked AI editing of notes — command surface, suggestion-mode change semantics, accept/reject review, attribution.
- `collab/agent-peer`: server-side actors applying schema-valid, conflict-free edits through the collaborative session — authentication/grants, presence, high-level edit operations.

### Modified Capabilities

<!-- none — openspec/specs/ is currently empty -->

## Impact

- `packages/editor`: new suggestion mark extensions (insertion/deletion + actor attrs), accept/reject commands, `NOTE_SCHEMA_VERSION` bump (**BREAKING** — old clients go read-only until refresh; batch with UniqueID).
- `apps/web`: review UI (inline widgets + summary bar), "Edit with AI" in `EditorBubbleMenu` + slash command, agent-aware caret rendering in `useNoteEditor`.
- `api` (Rails): AI edit endpoint (instruction + range → edit operations), agent grant model + token issuance, pilot job migration behind a feature flag.
- `apps/sync-server`: agent token validation in `onAuthenticate`, HTTP edit facade (high-level ops, markdown/HTML ingestion through the schema, rate limits), attribution callbacks.
- Deploy coupling: API + sync-server together (token path); the schema bump follows the established schema-version rollout; web can trail for caret rendering but not for the review UI.
