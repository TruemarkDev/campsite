# Spec: editor/human-suggesting

## Purpose

Provide a reviewable, attributed human editing workflow for collaborative notes while preserving one accepted version for public and downstream consumers.

## ADDED Requirements

### Requirement: SwR-HS-1 — Suggesting mode is explicit and per user

The system SHALL offer an **Editing / Suggesting** control only to authenticated users who already have edit access to the note. The selected mode SHALL apply only to that user's current editor instance, SHALL default to Editing whenever a note is newly opened, and SHALL NOT change another collaborator's mode.

**Verification:** Test

#### Scenario: Editor enters Suggesting mode

- **WHEN** a user with note edit access selects Suggesting
- **THEN** the editor visibly indicates Suggesting is active for that user while collaborators retain their own modes

#### Scenario: Viewer cannot enter Suggesting mode

- **WHEN** a user without note edit access opens the note
- **THEN** the Editing / Suggesting control and human suggestion creation actions are unavailable

#### Scenario: Mode resets on a new editor session

- **WHEN** a user closes a note while Suggesting is active and later opens it again
- **THEN** the note opens in Editing mode without changing or resolving existing suggestions

### Requirement: SwR-HS-2 — Human text edits become reviewable suggestions

While Suggesting is active, a plain-text insertion, deletion, or replacement contained within one existing text block SHALL create an attributed suggestion instead of directly changing accepted content. Deleted text SHALL remain present as a proposed deletion, inserted text SHALL remain present as a proposed insertion, and both halves of a replacement SHALL share one batch identity.

The system SHALL also let an editor select a non-empty text range and invoke **Suggest edit** to propose replacement text without first enabling the persistent Suggesting mode.

**Verification:** Test

#### Scenario: Typing creates an insertion suggestion

- **WHEN** an editor types text inside an existing paragraph while Suggesting is active
- **THEN** the text appears as an attributed insertion suggestion and accepted content remains unchanged

#### Scenario: Deletion preserves the original text

- **WHEN** an editor deletes accepted text inside one text block while Suggesting is active
- **THEN** the original text remains reviewable as a deletion suggestion and can be restored exactly by rejection

#### Scenario: Replacement is one review unit

- **WHEN** an editor replaces a selected text range while Suggesting is active
- **THEN** the proposed deletion and insertion appear as one suggestion batch with one accept or reject decision

#### Scenario: Selected-range suggestion

- **WHEN** an editor selects accepted text, invokes Suggest edit, and supplies replacement text
- **THEN** the replacement appears as a human-authored suggestion without directly changing accepted content

#### Scenario: Plain-text paste is suggested

- **WHEN** an editor pastes plain text inside one text block while Suggesting is active
- **THEN** the pasted text is captured as one insertion suggestion batch

### Requirement: SwR-HS-3 — Unsupported edits fail closed

While Suggesting is active, the system SHALL NOT silently apply an edit that cannot be represented and reversed by the v1 text suggestion model. Formatting changes, paragraph splits or merges, block-type conversions, list/table commands, attachments, rich-structure paste, and drag/drop SHALL be unavailable or refused with an explanation and a route back to Editing mode. Refusing an operation SHALL leave the document unchanged.

**Verification:** Test

#### Scenario: Structural command is refused

- **WHEN** an editor invokes a table, attachment, block conversion, or paragraph-boundary command while Suggesting is active
- **THEN** the system explains that the operation requires Editing mode and does not mutate the document

#### Scenario: Rich paste requires a safe choice

- **WHEN** an editor pastes structured rich content while Suggesting is active
- **THEN** the system offers a non-mutating choice to paste as plain text, switch to Editing, or cancel

### Requirement: SwR-HS-4 — Suggestions are grouped and attributed durably

The system SHALL group logically contiguous edits by one author into reviewable batches rather than creating one batch per keystroke. A selection move, explicit command, paste, editor blur, mode change, remote document change, or change of edit kind SHALL end the current batch.

Every batch SHALL have a stable unique identity, authenticated proposing organization membership, display attribution, creation time, and pending or resolved status. Author identity used for audit and authorization SHALL come from the authenticated server context and SHALL NOT be trusted from client-supplied mark attributes.

**Verification:** Test

#### Scenario: Contiguous typing is grouped

- **WHEN** an editor types adjacent characters without crossing a batch boundary
- **THEN** the review surface presents the characters as one suggestion batch

#### Scenario: Selection movement starts a new batch

- **WHEN** an editor moves the selection after creating a suggestion and begins another edit
- **THEN** the second edit receives a different batch identity

#### Scenario: Forged attribution is ignored

- **WHEN** a client submits a proposal registration containing another member's identity
- **THEN** the durable batch is attributed to the authenticated member and the forged identity is not recorded

### Requirement: SwR-HS-5 — Suggestions persist and collaborate without reprocessing

Pending human suggestions SHALL survive reload and SHALL synchronize to connected collaborators through the note's existing collaborative state. An incoming remote suggestion transaction SHALL NOT be transformed into another suggestion, and one user's local Suggesting mode SHALL NOT affect how another user's local or remote transactions are interpreted.

Authenticated note viewers SHALL be able to inspect suggestion markup and attribution but SHALL NOT be able to create or resolve suggestions without edit access.

**Verification:** Test

#### Scenario: Second client receives a human suggestion

- **WHEN** one editor creates a human suggestion while another client has the note open
- **THEN** the second client receives the same batch identity, content, and authenticated attribution exactly once

#### Scenario: Suggestion survives reload

- **WHEN** all clients close a note containing a pending human suggestion and an authorized user later reopens it
- **THEN** the pending suggestion is still present and reviewable

#### Scenario: Viewer inspects without resolving

- **WHEN** an authenticated viewer opens a note with pending suggestions
- **THEN** the viewer can identify the proposed changes and author but has no accept, reject, or suggestion-creation controls

### Requirement: SwR-HS-6 — Undo is local and does not reverse shared decisions

Undo while Suggesting is active SHALL undo the current user's most recent unresolved local suggestion edit as one logical unit. Undo SHALL NOT remove a collaborator's suggestion, reverse an authoritative resolution, or reintroduce a batch that has already been resolved.

**Verification:** Test

#### Scenario: Undo removes a local insertion batch

- **WHEN** an editor creates one contiguous insertion suggestion and invokes undo before resolution
- **THEN** that local pending insertion is removed as one undo operation

#### Scenario: Undo cannot reverse a remote resolution

- **WHEN** another editor resolves a suggestion and the local user invokes undo
- **THEN** the resolved outcome remains applied for every collaborator

### Requirement: SwR-HS-7 — Resolution has one authoritative outcome

Accepting or rejecting a suggestion SHALL be authorized and arbitrated before the shared document is destructively changed. The first valid resolution recorded for a pending batch SHALL become its only outcome; repeated requests for the same outcome SHALL be idempotent, and a competing outcome SHALL return the already-selected result without applying another document mutation.

If application to collaborative state fails after an outcome is selected, the batch SHALL remain visibly unresolved or resolving and SHALL be retried idempotently until the selected outcome is applied. Clients SHALL NOT report completion before the shared document and durable batch state agree.

**Verification:** Test

#### Scenario: Concurrent opposing resolutions converge

- **WHEN** two editors concurrently request accept and reject for the same pending batch
- **THEN** exactly one outcome is selected and every connected or later client converges to that outcome without losing both the original and proposed text

#### Scenario: Duplicate resolution is idempotent

- **WHEN** a client retries a successful resolution request
- **THEN** the same outcome is returned without creating another content mutation or activity event

#### Scenario: Collaborative application is retried

- **WHEN** the authoritative outcome is recorded but the collaborative document cannot be updated
- **THEN** the system exposes a non-final resolving state and later applies the selected outcome without selecting a different result

### Requirement: SwR-HS-8 — Unresolved suggestions do not alter committed content

The collaborative review document SHALL retain pending suggestion marks, but every committed-content projection SHALL exclude pending insertions and retain pending deletions with suggestion metadata removed. This contract SHALL apply to persisted `description_html`, public/read-only rendering outside the review surface, search, notifications, Slack, exports, previews, thumbnails, and plain-text extraction.

Accepting a batch SHALL update committed projections to the proposed result; rejecting it SHALL leave committed projections equivalent to their pre-suggestion content.

**Verification:** Test

#### Scenario: Pending insertion is not published

- **WHEN** a human or AI insertion suggestion remains unresolved
- **THEN** the inserted text is visible in authorized review UI but absent from public notes and every downstream committed-content projection

#### Scenario: Pending deletion remains committed

- **WHEN** accepted text is marked as a pending deletion
- **THEN** public and downstream committed-content projections continue to contain that text until the deletion is accepted

#### Scenario: Acceptance updates all projections

- **WHEN** an editor accepts a pending replacement and collaborative persistence completes
- **THEN** subsequent public, search, notification, Slack, export, preview, thumbnail, and plain-text projections contain the accepted replacement and no suggestion metadata

### Requirement: SwR-HS-9 — Proposal and resolution activity is auditable

The note activity trail SHALL record each durable human suggestion batch once and each authoritative resolution once, including authenticated proposer or resolver, batch identity, creation or resolution time, and final outcome. Failed, duplicate, or losing concurrent requests SHALL NOT create contradictory activity.

**Verification:** Test

#### Scenario: Human proposal appears in activity

- **WHEN** a human suggestion batch is durably registered
- **THEN** the note activity trail identifies the authenticated proposing member and batch

#### Scenario: Resolution appears once

- **WHEN** a pending batch is resolved and clients retry or race the request
- **THEN** the activity trail contains one resolution with the authoritative resolver and outcome

### Requirement: SwR-HS-10 — Suggesting and review are accessible and responsive

The mode selector, suggestion status, author attribution, navigation, and resolution controls SHALL have unique accessible names, visible keyboard focus, and keyboard operation. Mode changes and resolution results SHALL be announced without moving focus unexpectedly. The same creation and review flow SHALL remain operable on narrow and touch viewports without relying on hover or drag interactions.

**Verification:** Demonstration and Test

#### Scenario: Keyboard-only suggesting and review

- **WHEN** an editor uses only a keyboard to enter Suggesting, create a text suggestion, navigate to it, and resolve it
- **THEN** every action is reachable, visibly focused, uniquely named, and announced with focus retained in a predictable location

#### Scenario: Touch review

- **WHEN** an editor reviews suggestions on a narrow touch viewport
- **THEN** author details and accept/reject controls are available without hover and remain within the viewport

### Requirement: SwR-HS-11 — Compatibility failures are fail-closed

Suggesting controls SHALL remain unavailable until the web client, API, and sync service advertise compatible human-suggestion and authoritative-resolution behavior. If implementation changes persisted note schema or suggestion attributes, the system SHALL increment the note schema version and SHALL make older clients read-only before they encounter unsupported content.

**Verification:** Test and Inspection

#### Scenario: Partial deployment does not expose Suggesting

- **WHEN** a web client reaches an API or sync service that does not support authoritative human suggestions
- **THEN** the client remains in Editing mode and does not offer suggestion creation or local-only resolution

#### Scenario: Persisted schema changes are version-gated

- **WHEN** implementation adds or changes persisted suggestion attributes
- **THEN** the note schema version is incremented and a client on the previous version is read-only until refreshed
