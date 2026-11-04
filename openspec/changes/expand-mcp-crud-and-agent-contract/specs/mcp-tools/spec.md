## ADDED Requirements

### Requirement: Every MCP tool advertises an agent-readable contract

Every registered tool SHALL advertise an output schema, standard MCP safety
annotations, required OAuth scopes, and a category.

#### Scenario: Client lists tools

- **WHEN** an authorized client calls `tools/list`
- **THEN** every tool includes `inputSchema`, `outputSchema`, `annotations`, and
  Campsite contract metadata

### Requirement: Routine content CRUD reuses existing authorization

The MCP server SHALL expose bounded CRUD for comments, follow-ups, reactions,
messages, projects, posts, notes, attachments, favorites, read state, and project
pins. Every operation SHALL resolve the organization, require its existing OAuth
scope, authorize through Pundit, and use the existing domain mutation path.

#### Scenario: Authorized agent corrects its message

- **WHEN** an agent with `write_message` updates a message it may edit
- **THEN** Campsite updates it through the message-thread domain service and returns
  the serialized message

#### Scenario: Agent attempts an unauthorized mutation

- **WHEN** the OAuth scope or Pundit permission is missing
- **THEN** the tool returns a structured error and changes no state

### Requirement: Destructive and privileged boundaries remain explicit

State-removing operations SHALL advertise `destructiveHint: true`. Hard-delete,
bulk mutation, membership, sharing, integration, OAuth administration, export, and
raw collaboration-state tools SHALL NOT be registered.

#### Scenario: Client inspects lifecycle tools

- **WHEN** a client lists tools
- **THEN** archive, discard, cancel, and remove tools are marked destructive and no
  excluded privileged or bulk tool is present

### Requirement: Collaborative note edits use replica-safe coordination

`edit_note` SHALL use a short-lived agent sync grant and `AgentNoteEditor`, revoke the
grant after the call, and SHALL NOT directly replace note HTML or collaboration state.

#### Scenario: Human editor is active

- **WHEN** the sync facade rejects an agent edit because a human is active
- **THEN** `edit_note` returns a structured conflict error and preserves the note
