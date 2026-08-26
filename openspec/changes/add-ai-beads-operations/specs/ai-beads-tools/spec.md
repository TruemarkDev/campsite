## Purpose

Let people use AI to draft and operate channel-attached Beads through the same
bounded authorization and repository-execution contracts as human Board actions.

## ADDED Requirements

### Requirement: SyR-22 — AI produces a structured draft, never executable input

The system SHALL allow a user to request a Bead draft from an explicit bounded
selection of channel content. It SHALL reauthorize each selected object,
provide only selected safe text and allowlisted current Board metadata to the
model, require structured output, and deterministically validate the output
after inference. Model output SHALL NOT choose a command, flag, path, source,
permission, grant, or approval mode.

**Verification:** Inspection + Test

#### Scenario: User drafts a new Bead with AI

- **WHEN** an authorized user supplies an instruction and selected accessible
  context
- **THEN** AI returns a reviewable bounded draft and no operation is queued

#### Scenario: Selected object is no longer accessible

- **WHEN** the user loses access before server-side context retrieval
- **THEN** drafting is rejected without sending that object's content to the
  model

### Requirement: SyR-23 — Suggestion is the default autonomy mode

Every agent/source pair SHALL default to `suggest_only`. `approval_required`
and `bounded_autonomous` SHALL require explicit source-specific configuration by
an authorized source manager. Bounded autonomy SHALL be limited by action,
rate, field, and source policies and SHALL remain disabled at rollout until its
separate security and UAT gate is approved.

**Verification:** Test + Inspection

#### Scenario: Newly attached agent drafts work

- **WHEN** an agent-capable application has no Beads grant
- **THEN** it MAY return a suggestion from data it can read but cannot enqueue a
  Beads operation

#### Scenario: Bounded agent exceeds its grant

- **WHEN** an autonomous agent requests a disallowed action, field, rate, or
  source
- **THEN** the server rejects it before queueing and records a safe denial audit

### Requirement: SyR-24 — MCP tools reuse the operation domain and OAuth policy

The MCP server SHALL expose bounded Board/source read tools and MAY advertise
write tools for create, update, claim, close, reopen, add-dependency, and
remove-dependency only when those actions are enabled. Each write tool SHALL
require `mcp`, `write_beads`, the initiating user's `operate_beads?` policy, the
matching source action grant, and the same schemas, approval, precondition, and
receipt handling as REST. No MCP tool SHALL expose shell, raw Beads, Git, Dolt,
sync, delete, bulk, or repository file operations.

**Verification:** Inspection + Test

#### Scenario: Authorized MCP agent requests create

- **WHEN** all scopes, policies, grants, source state, and approval requirements
  pass
- **THEN** the tool returns a Pending operation or verified final receipt and
  does not claim success from queue acceptance alone

#### Scenario: Client lists tools before an action is enabled

- **WHEN** create is enabled but close and dependency mutation have not passed
  their release gates
- **THEN** `tools/list` advertises create but not the disabled write tools

### Requirement: SyR-25 — AI cannot silently resolve ambiguity or duplicates

The system SHALL present likely duplicate, parent, and dependency candidates as
advice. AI SHALL NOT silently merge, suppress, update, close, reparent, or
rewire work. Conflict and Unknown outcomes SHALL be returned to the initiating
human or agent as structured states requiring re-read and, when applicable,
new approval.

**Verification:** Test

#### Scenario: Similar Bead already exists

- **WHEN** AI finds a likely match while drafting create
- **THEN** it presents the candidate and keeps create/update as an explicit
  user or separately granted action

#### Scenario: Agent receives Unknown

- **WHEN** an executor cannot prove whether a mutation applied
- **THEN** the agent reports Unknown and cannot automatically retry, claim
  success, or choose a compensating action

### Requirement: SyR-26 — Agent roster describes grants without claiming presence

The safe channel agent roster MAY display Can suggest Beads work and Can operate
Beads roles derived from current source grants. It SHALL NOT expose scopes,
tokens, grant internals, operation history, or source details to unauthorized
viewers, and SHALL continue to label runtime status as Attached rather than
Online, Idle, Offline, available, or executing.

**Verification:** Test + Demonstration

#### Scenario: Agent has approval-required create grant

- **WHEN** an authorized channel member views the roster
- **THEN** the agent is shown as Attached and Can operate Beads with an approval
  requirement, without an online claim

#### Scenario: Grant is revoked

- **WHEN** a manager revokes the agent's last source action grant
- **THEN** its operator role disappears while its independent Attached roster
  status remains if the application is still attached

### Requirement: SyR-27 — AI privacy and provenance are visible

The draft flow SHALL identify the model/provider, selected context, resulting
fields, initiating user, agent/application when present, and whether existing AI
privacy controls retain prompts or responses. It SHALL NOT persist hidden model
reasoning. Every queued AI-derived operation SHALL retain safe provenance and a
digest of the approved normalized payload without placing private provenance or
credentials into the Beads issue.

**Verification:** Inspection + Test

#### Scenario: User reviews an AI draft

- **WHEN** the draft is ready for approval
- **THEN** the UI shows provider/model disclosure, selected sources, exact
  outgoing fields, and applicable retention behavior

#### Scenario: Receipt is inspected

- **WHEN** an AI-derived operation completes
- **THEN** Campsite can attribute the request and approved payload without the
  receipt or Bead containing chain-of-thought, tokens, emails, or hidden context
