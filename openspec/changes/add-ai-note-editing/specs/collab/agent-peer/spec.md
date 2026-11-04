# Spec: collab/agent-peer

## Purpose

Infrastructure for server-side actors (AI jobs) to apply edits to notes through the collaborative session: scoped authentication, schema-valid conflict-free application, visible presence during live operations, and high-level operations so producers need no CRDT knowledge. Subordinate to `editor/ai-note-editing`, which defines how such edits surface to humans.

## ADDED Requirements

### Requirement: Agent authentication with scoped write grants

The system SHALL issue sync credentials to registered non-human actors granting access to explicitly specified notes only, carrying the agent's identity. The sync layer SHALL reject connections or operations whose credential does not grant the target note, applying the same organization/resource authorization as human connections. Grants SHALL be revocable; revocation takes effect at the next authorization re-check.

#### Scenario: Valid grant

- **WHEN** an agent presents a credential granting write to note N and targets N
- **THEN** the operation is accepted and attributed to the agent's identity

#### Scenario: Ungranted note

- **WHEN** an agent presents a credential for note N but targets note M
- **THEN** the operation is rejected and no state of M is exposed

#### Scenario: Revocation

- **WHEN** an agent's grant is revoked during a session
- **THEN** subsequent operations fail at the next re-check and no further edits from it are applied

### Requirement: Edits are schema-valid and conflict-free

Agent edits SHALL be validated against the note schema before application; invalid content SHALL be rejected with a descriptive error, leaving the document unchanged. Applied edits SHALL merge with concurrent human edits by the same conflict resolution as human-to-human collaboration; no concurrent human edit may be lost.

#### Scenario: Concurrent edits converge

- **WHEN** a human types in one paragraph while an agent operation modifies another
- **THEN** both changes survive and all clients converge to the same document

#### Scenario: Invalid content

- **WHEN** a producer submits content that does not parse into the note schema
- **THEN** the operation fails with an error identifying the problem and the document is unchanged

### Requirement: High-level edit operations

The system SHALL expose an authenticated server-side interface with at minimum: replace entire content, append a section, replace an anchored section, and stream text incrementally — applied through the live session when one exists (viewers see changes in real time) and safely against persisted state when none does. Producers SHALL be able to request suggestion-mode application (per `editor/ai-note-editing`) or direct application; direct application SHALL be refused when the caller requests it for a note with active human editors unless explicitly overridden.

#### Scenario: Streamed edit with viewers

- **WHEN** a producer streams text into a note that viewers have open
- **THEN** viewers see the text arrive incrementally and the final persisted state equals what viewers saw

#### Scenario: Edit with no active session

- **WHEN** an operation targets a note nobody has open
- **THEN** the persisted document state and derived HTML reflect the edit, identical to the outcome had a session been open

#### Scenario: Suggestion-mode application

- **WHEN** a producer applies an edit in suggestion mode
- **THEN** the changes land as attributed, resolvable suggestions per `editor/ai-note-editing`

### Requirement: Agent presence during live operations

While applying a live operation, the agent SHALL publish presence (display name, agent marker, position) so connected humans see an attributed caret; presence SHALL clear when the operation completes or fails. Clients that predate the agent marker SHALL degrade gracefully to standard caret rendering.

#### Scenario: Watching a stream

- **WHEN** an agent streams content into an open note
- **THEN** viewers see a labeled agent caret at the write position for the duration of the stream, and it disappears afterward
