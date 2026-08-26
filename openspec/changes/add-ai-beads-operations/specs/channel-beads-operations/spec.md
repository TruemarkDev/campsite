## Purpose

Apply bounded Beads task mutations requested from a Campsite channel while the
repository-side executor retains checkout and CLI custody and returns verifiable
results.

## ADDED Requirements

### Requirement: SyR-12 — Operations use a structured, bounded action catalog

The system SHALL represent every Beads mutation as a versioned structured
operation. It SHALL initially support create and MAY enable update, claim,
close, reopen, add-dependency, and remove-dependency only through separate
action schemas and grants. It SHALL NOT accept a shell command, raw CLI flag,
repository path, environment variable, remote URL, explicit issue id, bulk
payload, force option, no-cycle-check option, or arbitrary Beads subcommand.

**Verification:** Inspection + Test

#### Scenario: Member submits a valid create

- **WHEN** an authorized member submits bounded regular-task fields to an
  attached source with create enabled
- **THEN** the system records one Pending create operation with a normalized
  payload and does not yet claim that a Bead exists

#### Scenario: Client submits a raw command

- **WHEN** any client supplies a command string, CLI flag, repository path, sync
  action, force option, or unsupported task type
- **THEN** schema validation rejects it before an operation is queued

### Requirement: SyR-13 — Three independent gates authorize an agent write

The system SHALL require the initiating user's `operate_beads?` authorization,
the actor's matching source action grant, and `write_beads` OAuth consent for an
MCP write. Agent-capable classification or publisher/executor attachment alone
SHALL NOT grant mutation authority. Grants SHALL be source-specific,
action-specific, revocable, and editable only by an authorized source manager.

**Verification:** Test

#### Scenario: Authorized human creates through the Board

- **WHEN** a member with `operate_beads?` confirms a create for an enabled source
- **THEN** the operation can be queued without requiring an agent grant

#### Scenario: Attached agent lacks one gate

- **WHEN** an MCP actor lacks `write_beads`, the matching source grant, kept
  attachment, agent classification, or its resource owner lacks
  `operate_beads?`
- **THEN** the system rejects the operation and changes neither queue nor Beads

### Requirement: SyR-14 — A source-bound executor claims one leased operation

The system SHALL allow only the source's attached executor application to claim
its pending operations. A claim SHALL create an opaque attempt id and bounded
lease, and at most one mutation lease SHALL be active per source. Completion
SHALL be accepted only from the same executor and attempt. Queue payloads SHALL
never choose the executor's binary, directory, environment, or network target.

**Verification:** Test + Demonstration

#### Scenario: Correct executor claims work

- **WHEN** the configured executor polls a source with one Pending operation
- **THEN** it receives one structured command and lease while a concurrent poll
  receives no second mutation lease

#### Scenario: Different connector submits a result

- **WHEN** another OAuth application or an expired/wrong attempt submits a
  receipt
- **THEN** the completion is rejected without changing operation or snapshot
  state

### Requirement: SyR-15 — Repository execution is exact, local, and non-syncing

The executor SHALL verify the configured Beads project id and invoke only the
documented action allowlist as a process argument array using `bd --sandbox
--actor <opaque-actor> -C <configured-repository> ... --json`. It SHALL pass
bounded content by structured arguments or stdin without a shell. It SHALL NOT
invoke Git, Dolt remote sync, raw SQL, backup, config, schema, memory,
infrastructure, formula, molecule, gate, wisp, delete, purge, import, or
repository-edit commands.

**Verification:** Inspection + Test

#### Scenario: Executor applies create

- **WHEN** a valid leased create reaches the configured matching workspace
- **THEN** the executor invokes the exact create command, does not invoke a
  shell or remote sync, and parses the native JSON result

#### Scenario: Source identity differs

- **WHEN** `bd context --json` reports a different project id than the executor
  configuration and queued source
- **THEN** the executor returns Conflict and runs no write command

### Requirement: SyR-16 — Revision and target preconditions prevent stale writes

Every operation SHALL include its draft source revision. The executor SHALL
compare it with the current Beads revision and SHALL verify target status,
updated time, and dependency preconditions for non-create actions. A create MAY
rebase across an unrelated revision only after idempotency lookup and all target
parent/dependency validations succeed. Other mismatches SHALL return a
structured Conflict without force or overwrite.

**Verification:** Test

#### Scenario: Target changed after draft

- **WHEN** a close, update, claim, reopen, or dependency operation targets a
  Bead whose relevant state changed after the draft
- **THEN** no mutation occurs and the caller receives safe current state for
  re-draft and re-confirmation

#### Scenario: Unrelated create revision changed

- **WHEN** a create's source revision changed but no operation marker exists and
  all referenced parents/dependencies remain valid
- **THEN** the executor MAY create it and records both drafted and applied
  revisions in the receipt

### Requirement: SyR-17 — Retries reconcile before execution

The executor SHALL attach a unique opaque `campsite_operation_id` metadata field
to every created issue and SHALL search exact metadata, including closed work,
before create or retry. One exact matching issue SHALL reconcile to success;
zero permits create; multiple or mismatched matches SHALL become Conflict or
Unknown. Expired leases and ambiguous update-like results SHALL be inspected
before retry and SHALL NOT be blindly repeated.

**Verification:** Test

#### Scenario: Create succeeded but receipt was lost

- **WHEN** the issue with the operation metadata exists after the attempt lease
  expires
- **THEN** the next reconciliation returns its real id without creating another
  issue

#### Scenario: Outcome cannot be proven

- **WHEN** postcondition reads cannot prove either success or no mutation
- **THEN** the operation becomes Unknown for human resolution and no automatic
  retry runs

### Requirement: SyR-18 — Receipts and snapshots report separate truths

The system SHALL mark Succeeded only after a valid native result and verified
postcondition. A safe receipt SHALL record operation/attempt ids, action,
opaque actors, issue id, source revisions before/after, normalized verification
summary, and timestamps. It SHALL exclude credentials, paths, environment, raw
commands, raw process output, stack traces, emails, and hidden model context.
After success the executor SHALL publish a fresh atomic Board snapshot; until
accepted, the UI SHALL say Applied; Board refresh pending and SHALL NOT move a
card optimistically.

**Verification:** Test + Demonstration

#### Scenario: Mutation succeeds but snapshot upload fails

- **WHEN** Beads verifies the write and the following snapshot cannot be
  accepted
- **THEN** the operation remains Succeeded with its receipt while the Board
  keeps its prior snapshot and displays refresh pending

#### Scenario: Command exits unsuccessfully

- **WHEN** the native command or postcondition verification fails
- **THEN** the operation is Failed, Conflict, or Unknown as appropriate and no
  success receipt or optimistic card state is produced

### Requirement: SyR-19 — Content crossing into Beads is explicitly disclosed

Before a human-approved write, the system SHALL show the target channel/source,
repository-audience warning, source revision, and exact normalized fields that
will be persisted to Beads. It SHALL write no unselected post, comment, message,
note, transcript, attachment, linked page, hidden prompt, model reasoning,
credential, private URL, or user email. Editing a reviewed payload SHALL
invalidate its prior approval digest.

**Verification:** Inspection + Test + Demonstration

#### Scenario: AI draft uses selected channel context

- **WHEN** a user selects one post and asks AI to draft a Bead
- **THEN** the review shows every derived field and citation before enqueue and
  omits unrelated channel history and attachments

#### Scenario: Draft changes after approval

- **WHEN** any persisted field, source, citation, or source revision changes
  after approval
- **THEN** the old approval cannot authorize the modified operation

### Requirement: SyR-20 — Lifecycle changes stop new execution without external rollback

Archive, source replacement/detach, connector or agent detachment, grant or token
revocation, and feature disablement SHALL stop new submission and claim. Pending
operations SHALL become Cancelled or Expired with a reason; claimed operations
SHALL reconcile before retry. Deleting a Campsite operation SHALL NOT invoke a
compensating Beads command. An undo SHALL be a separately authorized new
operation against current state.

**Verification:** Test

#### Scenario: Source is detached with queued work

- **WHEN** a manager detaches the source before its Pending operation is claimed
- **THEN** the operation is cancelled and the external workspace is untouched

#### Scenario: Source is detached during a claim

- **WHEN** detachment occurs after an executor could already have started a command
- **THEN** the operation is marked cancellation-requested and reconciled rather
  than blindly retried or compensated

### Requirement: SyR-21 — Board creation and operation status remain truthful

The Board SHALL provide an accessible New Bead flow to an authorized operator
and SHALL display Pending, Claimed, Succeeded, Failed, Conflict, Expired,
Cancelled, Unknown, and refresh-pending outcomes. Creation SHALL display the
real Beads id only after receipt. Disabled actions and agents SHALL identify the
missing permission, grant, approval, executor, or source state without exposing
private source details to unauthorized viewers.

**Verification:** Test + Demonstration

#### Scenario: User creates a Bead from Board

- **WHEN** an authorized user reviews and confirms a valid create and the
  executor verifies it
- **THEN** the UI progresses through truthful operation states and finally links
  the real id from the refreshed Board

#### Scenario: Executor is unavailable

- **WHEN** an approved operation remains unclaimed
- **THEN** the UI reports Pending and executor-unavailable/stale information
  without claiming that Beads changed
