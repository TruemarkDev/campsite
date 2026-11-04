# Design: add-human-suggesting-mode

## Context

See `proposal.md` for motivation and `specs/editor/human-suggesting/spec.md` for the behavior contract.

The as-built note editor already has the core persisted representation:

- `suggestionInsert` and `suggestionDelete` marks carry `actorId`, `actorType: 'ai' | 'user'`, `invokedBy`, `instruction`, `batchId`, and `createdAt`.
- `applySuggestion`, individual/bulk accept, and individual/bulk reject commands operate on those marks.
- Suggestion marks persist in Yjs, survive reload, render in the web editor, and are visible to a second collaborative client.
- `SuggestionReview` displays a summary and accept/reject controls; Rails records proposal and resolution timeline events.
- The AI note-editing design identifies human-to-human Suggesting UI as a follow-up and keeps format-change suggestions out of its v1.

The following gaps shape this design:

- ❌ **Unbuilt:** no user-facing Editing / Suggesting mode and no transaction transformer turns ordinary human typing or deletion into suggestion marks.
- ⚠️ **Non-conformant:** `resolveSuggestions(..., 'strip')` currently removes proposed deletions and keeps proposed insertions, so persisted `description_html` and non-editor renderers expose the proposed result before acceptance. `SwR-HS-8` makes the last accepted content authoritative instead.
- 🟡 **Partial:** collaboration coverage proves concurrent accept/accept convergence, but does not prove opposing accept/reject convergence. Resolution currently mutates Yjs in the client and records Rails activity afterward, leaving no single authority for a race or partial failure.
- 🟡 **Partial:** client mark attributes contain display attribution, but Rails authorization and activity are the only trusted actor sources. Human review needs durable server-owned batch identity and attribution.

`editor/human-suggesting` is authoritative for human suggestion creation and for the shared committed-content and resolution invariants. `editor/ai-note-editing` remains authoritative for AI invocation and generation. Where the two changes differ on unresolved derived content or resolution ordering, the stricter requirements in this change take precedence for every suggestion actor.

## Goals / Non-Goals

**Goals:**

- Reuse the existing suggestion schema and review primitives without a paid Tiptap package or a second track-changes representation.
- Preserve responsive local typing while making proposal identity and resolution server-authoritative.
- Keep every unsupported transaction from bypassing review semantics while Suggesting is active.
- Make committed/public/downstream content equal to the last accepted document state.
- Deliver one deployable text-first vertical slice with deterministic collaboration and rollback behavior.

**Non-Goals:**

- Suggestion creation by viewers, commenters, guests, public-note visitors, integrations, or agents beyond the existing AI/agent path.
- Reviewable formatting changes, paragraph splits/merges, block transformations, lists, tables, attachments, media galleries, drag/drop, or other atom/node changes.
- A general document version-history system or replacement for Yjs undo.
- Adoption of `@tiptap-pro/extension-tracked-changes` or a third-party track-changes runtime dependency.
- Changing the existing persisted suggestion attributes unless implementation proves a schema change unavoidable.

## Decisions

### 1. Extend the existing two-mark model

Human suggestions use the existing insertion/deletion marks and `batchId` pairing. A new functionality extension owns mode state, transaction rewriting, eligibility checks, and transaction metadata; it does not introduce another persisted mark or node.

This keeps AI and human review on one renderer, one set of commands, one Yjs representation, and one committed-content transformer. The alternative—installing Tiptap Pro or the MIT reference package—would introduce competing schemas and commands, new dependency/release custody, and uncertain compatibility with Campsite's custom note nodes and Hocuspocus graph.

No `NOTE_SCHEMA_VERSION` bump is planned. Any implementation change to persisted attributes or node/mark structure changes that decision and requires the established schema-version gate before release.

### 2. Intercept only eligible local text transactions

The first-party extension uses Tiptap's transaction middleware with higher priority than ordinary editor plugins. When local Suggesting is active, it inspects the incoming transaction against the pre-transaction document and produces a replacement transaction marked with a private origin/skip metadata key.

Eligible transactions are plain-text insertion, deletion, or replacement wholly inside one existing text block. A replacement marks the old range as deletion and the new text as insertion with the same batch. Plain-text paste is one insertion batch. The selected-range **Suggest edit** action calls the same transformation path explicitly.

The transformer bypasses:

- remote Yjs transactions identified by the existing remote-transaction guard,
- server/facade suggestion application,
- authoritative accept/reject application,
- migrations and derived-only document work,
- selection-only transactions, and
- its own tagged output.

Any document-changing transaction outside the eligible set is rejected while Suggesting is active. The web surface disables known unsupported controls, while the extension remains the final fail-closed boundary for keyboard, paste, plugin, and programmatic paths. Silent fallback to direct editing is prohibited.

Rewriting `ReplaceStep`/text slices at the transaction boundary was selected over DOM `beforeinput` handlers because commands, paste, accessibility input, and programmatic editor operations all converge at the transaction boundary. Appending a second transaction after the original was rejected because deleted content would already be gone and remote collaborators could observe an intermediate direct edit.

### 3. Keep mode and batching local

Mode is extension storage owned by one editor instance. The web control calls `setHumanSuggestionMode('edit' | 'suggest')`; opening a note creates a fresh instance in Editing. Mode is not persisted into note content and is not broadcast as a document mutation.

A local batch remains open only for adjacent edits by the same authenticated author, in the same text block, with the same edit kind. Selection movement, explicit commands, paste, blur, mode changes, remote document changes, or edit-kind changes close it. This yields review-sized changes without a network-defined timing threshold and gives undo one logical local batch.

### 4. Register batches optimistically but treat Rails identity as authoritative

The client generates an opaque batch UUID so typing does not wait on the network, applies eligible marks locally, and idempotently registers the batch with Rails using the authenticated note session. Until registration succeeds, the review UI shows the batch as syncing and disables resolution.

A new durable `NoteSuggestionBatch` record owns:

- note and unique batch identity,
- source (`human`, `ai`, or `agent`),
- authenticated proposer membership/application identity,
- pending/resolving/accepted/rejected lifecycle,
- selected outcome and authenticated resolver,
- proposal/resolution timestamps, and
- application attempt/error metadata needed for retry without storing document content.

The unique key is `(note_id, batch_id)`. Rails ignores client-supplied actor identity and derives the proposer from the authenticated principal. Existing AI and agent proposal paths register through the same model. Legacy unresolved batches can be registered lazily from their existing trusted proposal timeline event when first reviewed.

If registration is temporarily unavailable, the suggestion remains pending and excluded from committed projections. If registration is terminally unauthorized, the API requests an idempotent rejection through the sync facade so forged or stale-session marks do not remain indefinitely.

An alternative that sends every keystroke through Rails was rejected because network latency would own the typing loop. Treating mark attributes as authoritative was rejected because an editor client can forge them.

### 5. Resolve through a server-arbitrated state machine

The web client no longer runs destructive accept/reject commands first. It requests resolution from Rails with a batch identity, desired outcome, and idempotency key.

Rails locks the durable batch. A pending batch records the first valid outcome and enters `resolving`; the same request can retry, while an opposing request receives the selected outcome. Rails then invokes the sync-server's existing direct-connection/facade boundary. The sync server loads the current collaborative document, applies the shared accept/reject command once, stores Yjs state plus committed HTML, and returns the observed result. Rails marks the batch accepted/rejected and creates one resolution activity event.

If collaborative application fails, the selected outcome remains immutable in `resolving` and a job retries the idempotent sync operation. Clients display resolving as non-final and wait for the shared document. Bulk resolution enumerates durable pending batches through this same path; it does not call the current client-only accept-all/reject-all commands.

This state machine was selected over client-first mutation because cross-client accept/reject races otherwise have two destructive winners. A Yjs map alone was rejected because choosing a convergent resolution value after both clients have already deleted opposite text cannot reconstruct the lost alternatives.

### 6. Split review state from committed projections

The shared resolver gains explicit meanings:

- `review`: preserve suggestion marks and both alternatives for authorized collaborative review.
- `committed`: remove pending insertions, retain pending deletions, and strip suggestion metadata.
- `proposed`: remove pending deletions, retain pending insertions, and strip suggestion metadata for deliberate previews only.

The ambiguous `strip` mode is retired after all call sites are classified. Sync-server persistence generates `description_html` from `committed`. Public/read-only rendering outside the authenticated review surface, search, Slack, notifications, exports, previews, thumbnails, and plain text consume `committed`. The collaborative editor continues to render `review` from Yjs state.

This reverses the current proposed-result projection for unresolved AI suggestions as well as human suggestions. It aligns the implementation with the existing promise that suggestions do not become accepted content until resolution and prevents unapproved text from leaving the review boundary.

### 7. Preserve collaboration and undo origins

Transformed local suggestion transactions retain the local collaboration origin so Yjs UndoManager can group and undo them. Remote transactions, proposal registration updates, and server resolution transactions use distinct origins and are excluded from the local undo stack. Once a durable batch enters resolving or resolved state, the client cannot undo its outcome; a new edit or suggestion is required.

Tests cover local undo, remote arrival, edits adjacent to pending marks, reconnect/reload, concurrent human typing, concurrent human/AI suggestions, duplicate resolution, and opposing resolution.

### 8. Gate the three-service compatibility unit

A disabled-by-default `human_suggesting_mode` feature gate controls the web entry points. The API and sync server expose compatible capability/version information; the web only enables the gate when both support durable batch registration and authoritative resolution. The mode extension can remain registered while hidden because it adds no persisted schema by itself.

This permits API/sync preparation before web exposure and makes rollback a gate change rather than a document migration.

## Risks / Trade-offs

- **[Optimistic batch registration can leave temporary orphan marks]** → Unregistered batches are visibly syncing, cannot be resolved, never enter committed projections, retry automatically, and are authoritatively rejected after a terminal authorization failure.
- **[Transaction interception can miss an editor mutation path]** → The extension is the fail-closed boundary; tests exercise keyboard input, IME composition, paste, commands, programmatic chains, mobile input, and custom node views. Unknown document-changing steps are rejected rather than applied directly.
- **[Large or complex scripts can be split incorrectly]** → Use ProseMirror text slices and grapheme-safe input behavior rather than JavaScript string offsets; cover RTL, CJK, emoji, combining marks, and IME composition.
- **[Rails and Yjs state can disagree during an outage]** → The immutable `resolving` outcome plus idempotent facade application provides reconciliation; clients do not announce completion until both states agree.
- **[Committed-content correction changes current AI suggestion output]** → Treat it as the declared breaking change, regenerate derived HTML before enabling the feature, and verify public/search/Slack samples against both pending insertions and deletions.
- **[Unsupported structure editing makes v1 feel constrained]** → Keep the scope visible in the mode UI, provide selected-range Suggest edit as the high-value path, and require a separate schema/design change before expanding to format or node suggestions.
- **[Feature gate rollback leaves pending marks]** → Existing review UI and authoritative resolution remain available; disabling creation does not delete or auto-resolve content.
- **[Third-party reference code creates license or compatibility drift]** → Use the MIT project and ProseMirror example as design references only. If implementation copies substantial code, retain the required license notice and record provenance; do not add the package dependency implicitly.

## Migration Plan

1. Add the durable batch model, authorization, registration/resolution APIs, retry job, and feature gate with creation disabled. Existing AI/agent proposal paths begin registering new batches without changing their UI.
2. Deploy the sync-server authoritative resolution operation and explicit `review` / `committed` / `proposed` transformers. Keep existing clients compatible and continue accepting legacy client-side resolutions during the migration window while logging them as legacy.
3. Dry-run and then regenerate `description_html` from `committed` Yjs state for notes at the suggestion-capable schema version. The backfill does not rewrite Yjs state; failures remain reported and retryable.
4. Deploy the web mode extension, UI, registration status, and server-first review controls behind `human_suggesting_mode`.
5. Run desktop, mobile, keyboard, two-client, reconnect, opposing-resolution, public/share, search, Slack, notification, export, preview, and rollback acceptance against the homelab deployment.
6. Enable the gate for an internal cohort, verify no unresolved proposal appears in committed projections, then widen deliberately.

Rollback disables new human suggestion creation first. Pending batches remain reviewable and resolvable through the authoritative path. The durable table, committed-content semantics, and schema-compatible marks remain in place; rollback does not delete batch records, strip Yjs marks, or restore the unsafe proposed-result projection.
