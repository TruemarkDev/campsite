# Spec: editor/ai-note-editing

## Purpose

Let a user ask AI to edit the note they are working in, with every AI change arriving as a reviewable suggestion — visible in place, attributed, and individually acceptable or rejectable — rather than as a direct write.

## ADDED Requirements

### Requirement: User-invoked AI edits from within the note

A user with edit access SHALL be able to invoke an AI edit on a selection (via the selection menu) or at the cursor (via a command), providing a natural-language instruction. The AI's response SHALL be applied to the targeted range of that note. Invocation SHALL be unavailable to users without edit access.

#### Scenario: Rewrite a selection

- **WHEN** a user selects a paragraph, chooses "Edit with AI," and instructs "make this more concise"
- **THEN** the paragraph's proposed replacement appears in place as suggested changes scoped to the selected range

#### Scenario: Insert at cursor

- **WHEN** a user invokes an AI command at the cursor with an instruction to draft content
- **THEN** the drafted content appears at the cursor position as a suggested insertion

#### Scenario: Viewer without edit access

- **WHEN** a user with read-only access views a note
- **THEN** no AI edit invocation is offered

### Requirement: AI changes land as suggestions, not direct writes

When a human is present in the editing context, AI-produced changes SHALL be recorded as suggestions: proposed insertions and deletions that are visually distinct, attributed to the AI actor, and do not alter the effective (accepted) content until a human resolves them. Suggested content SHALL persist with the document (survives reload and collaborative sync) until resolved.

#### Scenario: Suggestion rendering

- **WHEN** an AI edit is applied to a note
- **THEN** proposed insertions and deletions are visually distinguishable from accepted content and attributed to the AI actor

#### Scenario: Suggestions persist

- **WHEN** a note with unresolved suggestions is closed and reopened, or synced to another collaborator
- **THEN** the suggestions are intact, attributed, and still resolvable

#### Scenario: Concurrent human editing around suggestions

- **WHEN** a human edits text adjacent to an unresolved suggestion
- **THEN** the human's edit applies normally and the suggestion remains anchored to its content

### Requirement: Accept/reject review

Each suggestion SHALL be individually acceptable or rejectable by a user with edit access. The system SHALL offer bulk resolution ("accept all" / "reject all") for a note. Accepting materializes the proposed content as normal content; rejecting restores the prior content; both remove the suggestion markers. Resolution actions SHALL sync to all collaborators.

#### Scenario: Accept one suggestion

- **WHEN** a user accepts a suggested replacement
- **THEN** the proposed text becomes normal content, the replaced text is removed, and the suggestion markers disappear for all collaborators

#### Scenario: Reject one suggestion

- **WHEN** a user rejects a suggested insertion
- **THEN** the proposed text is removed and the document reads as if the suggestion never existed

#### Scenario: Bulk accept

- **WHEN** a user accepts all suggestions in a note
- **THEN** every unresolved suggestion is materialized in one action and the note contains no remaining suggestion markers

### Requirement: Attribution of AI edits and resolutions

Suggestions SHALL record the proposing actor (AI, with the invoking user where applicable); resolutions SHALL record the resolving human. The note's activity trail SHALL reflect both.

#### Scenario: Audit after review

- **WHEN** a user inspects note activity after AI suggestions were proposed and resolved
- **THEN** the trail shows the AI actor (and invoking user) for the proposal and the human who accepted or rejected it

### Requirement: Document format compatibility is versioned

Introducing suggestion markers changes the persisted note format. Clients that do not understand the new format SHALL be prevented from writing to affected notes via the existing schema-version mechanism, and SHALL regain access after upgrading.

#### Scenario: Stale client

- **WHEN** a client at the previous schema version opens a note after the suggestion format ships
- **THEN** it is placed in read-only mode and prompted to refresh, per the established schema-version behavior
