# Proposal: add-human-suggesting-mode

## Why

Campsite note editors can review AI-proposed changes, but people can only edit accepted content directly or leave a comment. The existing collaborative suggestion marks already support human actors, so Campsite can add a first-party, reviewable human editing workflow without adopting Tiptap's paid Tracked Changes extension.

## What Changes

- Add a per-user **Editing / Suggesting** control to collaborative notes for users who already have edit access.
- Add a text-first suggesting path: insertions, deletions, and replacements inside existing text blocks become attributed `suggestionInsert` / `suggestionDelete` batches instead of immediately accepted edits.
- Reuse the existing suggestion review UI and add human-friendly author attribution, batch navigation, and durable proposal/resolution activity.
- Add one authoritative resolution path so concurrent accept/reject requests select one durable outcome before the collaborative document is mutated.
- **BREAKING**: derived/public content SHALL represent the last accepted content while suggestions are unresolved; unapproved human or AI insertions SHALL NOT appear in search, notifications, Slack, exports, previews, or public notes until accepted.
- Implement the transaction behavior as a first-party `@campsite/editor` extension using existing Tiptap/ProseMirror APIs. No Tiptap Pro package or new track-changes dependency is introduced.
- Keep v1 deliberately bounded: users without edit access cannot suggest; formatting changes, paragraph splits/merges, block conversions, tables, attachments, drag/drop, and other structural edits are unavailable while Suggesting is active.

## Capabilities

### New Capabilities

- `editor/human-suggesting`: Human-authored, collaborative text suggestions; mode and permission behavior; attribution; committed-content isolation; deterministic review; accessibility; and compatibility requirements.

### Modified Capabilities

<!-- None. `add-ai-note-editing` is an unarchived change rather than a canonical spec. This change depends on its as-built suggestion schema and review primitives and explicitly defines the stronger shared resolution and committed-content contracts. -->

## Impact

- `packages/editor`: first-party Suggesting-mode transaction extension, transaction metadata/guards, batching rules, suggestion queries, and focused unit/collaboration tests. The existing suggestion marks remain the persisted representation; a note schema bump is not expected unless implementation changes their attributes.
- `apps/web`: mode selector, selected-range entry point, unsupported-action handling, human attribution, review-state feedback, and desktop/mobile/keyboard acceptance coverage.
- `api`: durable suggestion-batch proposal/resolution state and authorization; activity attribution; idempotent resolution API.
- `apps/sync-server`: authoritative batch application through the existing direct-connection/facade boundary, committed-content serialization, retry/reconciliation behavior, and opposing-resolution tests.
- Downstream consumers: `description_html`, public/read-only rendering, search, Slack, notifications, previews, thumbnails, and exports must consume accepted content rather than unresolved proposed content.
- Release coupling: API, sync-server, and web must deploy as one compatibility unit after migration/preflight; no Tiptap Cloud service or paid registry credential is required.
