## Why

The read-only channel Board makes repository work visible in Campsite, but a
member who turns a channel decision into work currently leaves the conversation,
find the correct checkout, and invoke Beads manually. Attached AI agents can
read and write Campsite content through MCP, but they have no bounded way to
create or operate the channel's authoritative Beads tasks.

This follow-up adds a deliberate write path without moving repository, Dolt,
Git, or sync custody into Campsite. Humans and AI can propose structured
operations; a source-bound executor in the repository applies only authorized
native `bd` commands and returns proof of the actual result.

❌ **Unbuilt:** `MAINTENANCE.md` currently forbids new product features, and
`add-channel-beads-board` is itself unbuilt. This change SHALL NOT be implemented
until stewardship policy explicitly permits it and the read-only source,
snapshot, authorization, and publisher contracts are available.

## What Changes

- A Board member with a new `operate_beads?` permission can draft and submit a
  regular Beads operation. Creation is the first enabled mutation; update,
  claim, close/reopen, and dependency changes are separately grantable.
- A repository-side executor pulls commands for one configured Beads source,
  validates the expected source identity and revision, invokes an exact native
  command allowlist with `bd --sandbox`, and returns a redacted execution
  receipt followed by a fresh read snapshot.
- Operations have explicit Pending, Claimed, Succeeded, Failed, Conflict,
  Expired, Cancelled, and Unknown states. The Board never moves a card or invents
  an issue id before Beads confirms the mutation.
- Creation uses a stable Campsite operation id in Beads metadata so a retry can
  reconcile an already-created issue. Ambiguous outcomes are inspected before
  retry; they are never blindly repeated.
- A dedicated `write_beads` OAuth scope and source-specific action grants gate
  AI/MCP mutation tools. Agent classification alone does not grant Beads write
  authority.
- AI defaults to suggestion mode. A native **Draft with AI** flow and MCP
  clients produce the same bounded Beads-operation draft, show the exact text
  that would cross from Campsite into the repository, and require the configured
  approval mode before enqueueing it.
- Project managers can opt a named attached agent into bounded autonomous
  actions per source. No grant permits raw shell, arbitrary `bd` flags, direct
  database access, Git/Dolt sync, deletion, bulk mutation, memories,
  infrastructure records, formulas, molecules, or repository configuration.
- Every request and receipt records human initiator, agent/application actor,
  source revision before and after, safe command kind, target/result issue id,
  timestamps, and a correlation id without recording credentials, repository
  paths, raw stderr, or hidden model context.

## Capabilities

### New Capabilities

- `channel-beads-operations`: source-bound command authorization, queue/lease
  lifecycle, repository execution, idempotency, conflict handling, receipts,
  snapshot reconciliation, and Board mutation UI.
- `ai-beads-tools`: reviewable AI drafting, explicit context disclosure,
  source-specific autonomy grants, and MCP read/write tools over the same
  operation domain.

### Modified Capabilities

- `channel-agent-roster`: when both changes are implemented, the safe roster can
  distinguish **Can suggest Beads work** and **Can operate Beads** grants from
  the existing **Attached** and **Beads publisher** roles without claiming live
  presence.

## Impact

- **Prerequisite:** the accepted and implemented `add-channel-beads-board`
  source, immutable snapshot, safe roster, and repository publisher contracts.
- **Rails API:** additive operation/grant/receipt persistence; Pundit policy;
  REST endpoints for drafts, confirmation, queue claim/lease, completion, and
  history; `write_beads` OAuth scope; MCP tools; serializers; generated client.
- **Web:** New Bead and task-operation flows, exact disclosure preview, AI draft
  review, per-operation status/receipt UI, conflict resolution, and agent grant
  controls on the Board.
- **Repository boundary:** an outbound-only executor is statically bound to one
  source and local checkout. It passes structured values as process arguments or
  stdin, never a shell string, and invokes only documented `bd` commands.
- **AI boundary:** model output is untrusted structured input. Deterministic
  server validation, permission checks, disclosure preview, and repository
  preconditions apply after inference and cannot be bypassed by a prompt.
- **Disclosure:** channel content can have a narrower audience than the Beads
  repository. No post, comment, note, message, attachment, transcript, or hidden
  prompt context crosses into Beads unless explicitly selected and shown in the
  final payload preview.
- **Dependencies:** no product library is selected by this proposal. Any model
  or executor dependency SHALL pass the repository's installation ritual at
  implementation time; existing Rails AI and MCP abstractions SHOULD be reused
  when they satisfy the contract.
- **Tracking:** Beads feature `campsite-4cl.1`, a child of the read-only Board
  feature `campsite-4cl`.
