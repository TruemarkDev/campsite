## Context

`add-channel-beads-board` deliberately stops at an immutable, read-only
projection. Campsite stores an opaque Beads project id and current source
revision, while a repository-side publisher owns the local checkout and invokes
`bd`. Those boundaries are prerequisites, not temporary shortcuts.

Campsite's MCP server already authenticates user-scoped OAuth tokens, requires
per-domain write scopes, dispatches structured JSON-Schema tools, and applies
Pundit authorization. It performs no model inference. The AI follow-up SHOULD
reuse that thin-tool pattern: an MCP agent and a native Campsite AI draft both
produce the same domain command and neither receives a generic repository
terminal.

The installed Beads 1.2.2 CLI provides the relevant native primitives:
`create --json --dry-run`, structured `update`, `close`, `reopen`, dependency
commands, `--actor`, `--sandbox`, custom metadata, and metadata filtering.
`--sandbox` prevents automatic Dolt remote push; it does not make a write
read-only. Repository-local Beads history remains controlled by Beads, while
remote sync remains a separate operator action.

Beads embedded mode is single-writer. The executor therefore needs a lease and
one-at-a-time mutation rule even when several humans or agents submit commands.
Network loss after a local mutation but before its receipt creates an ambiguous
outcome. Exactly-once execution cannot be inferred from an HTTP retry; creation
needs a durable operation marker and every other command needs inspection before
replay.

The data direction also introduces a new confidentiality risk. The read-only
Board sends an allowlisted repository projection into Campsite. A create/update
operation sends selected Campsite text into a repository whose readers can
differ. AI convenience SHALL NOT erase that boundary.

## Goals / Non-Goals

**Goals:**

- Create regular Beads tasks from the channel Board and return the real Beads id.
- Let authorized attached AI agents propose and, when explicitly granted,
  execute the same bounded operations through MCP.
- Keep the repository-side executor as the only component that receives a local
  checkout path or runs a Beads write command.
- Preserve source revision preconditions, operation idempotency, truthful status,
  safe receipts, and a complete Campsite-side audit trail.
- Make the exact channel-derived text and target source visible before it crosses
  the repository boundary.
- Support incremental grants: create, edit content/metadata, claim,
  close/reopen, and dependency changes are separate capabilities.

**Non-Goals:**

- Raw shell access, arbitrary CLI flags, `bd sql`, direct Dolt access, or a
  general remote-code-execution service.
- `bd dolt push/pull`, Git commit/push/merge, deployment, branch changes,
  backups, config changes, schema migration, or repository file editing.
- Hard delete, purge, bulk mutation/import, force close, `--no-cycle-check`,
  custom explicit issue ids, infrastructure/events/messages, memories, formulas,
  molecules, gates, wisps, or cross-repository routing.
- Treating a Board drag, optimistic UI state, AI statement, or accepted queue
  request as proof that Beads changed.
- Inferring agent availability, capacity, correctness, or trust from attachment,
  token use, or successful past operations.
- Automatically copying an entire thread, document, transcript, attachment, or
  hidden model prompt into a Bead.
- A guarantee of automatic remote sync. The executor mutates the configured
  local Beads workspace only; existing project/operator policy owns sync.

## Decisions

### A-12 — One operation domain serves humans, native AI, and MCP agents

Add `ProjectBeadsOperation` as the canonical desired-command record. The Board
UI, a native AI draft endpoint, and MCP tools all submit the same versioned
operation schema; none constructs a shell command. The server validates and
authorizes the final structured payload after any AI inference.

Creation fields are title, optional description, type, priority, assignee,
labels, parent id, dependencies, acceptance criteria, design, notes, estimate,
due/defer time, and an optional source-context citation list. Each field has
bounded size/count and an explicit disclosure classification. Types are limited
to regular project work (`bug`, `feature`, `task`, `epic`, `chore`, and
`decision`) unless the source advertises a narrower policy.

The initial action catalog is `create`, `update`, `claim`, `close`, `reopen`,
`add_dependency`, and `remove_dependency`. Each action has its own schema and
grant. Create SHALL be implemented and enabled first; later actions remain
disabled until their action-specific tests and UAT pass.

### A-13 — Permission, OAuth scope, and source grant are independent gates

Add `ProjectPolicy#operate_beads?` for human/user authorization and a dedicated
`write_beads` OAuth scope for MCP writes. A source-specific
`ProjectBeadsAgentGrant` maps one kept, agent-capable OAuth application to an
allowlist of actions and one autonomy mode. Removing the project membership,
agent classification, source binding, OAuth consent, or grant revokes future
operations.

`agent_capable` remains descriptive and SHALL NOT grant execution by itself. The
publisher/executor connector is also not automatically an AI operator. The
server checks the initiating user's project authorization even when an MCP
application has a source grant; an application cannot amplify its resource
owner's permissions.

Autonomy modes are:

- `suggest_only` (default): the agent can return a draft but cannot enqueue it;
- `approval_required`: a permitted human SHALL approve that exact normalized
  payload and source revision;
- `bounded_autonomous`: the named agent can enqueue only its explicitly granted
  actions within configured per-source rate and field limits.

Changing grants or autonomy requires `manage_beads_source?`, re-consent for the
scope where applicable, and an audit event. There is no organization-wide
blanket Beads operator toggle.

### A-14 — The executor pulls source-bound commands over outbound HTTPS

Extend the repository publisher with an executor mode, or ship a sibling
dependency-free entrypoint after verifying the installed Beads feature set and
official docs at implementation time. It is statically configured with one
Campsite source id, expected Beads project id, local repository directory, API
base URL, OAuth token environment variable, and `bd` binary. Queue payloads
never provide a filesystem path, binary path, URL override, environment
variable, raw argument, or shell fragment.

The executor long-polls or runs one-shot to claim one command with a bounded
lease. It re-runs `bd context --json` and `bd vc status --json`, compares the
configured source and operation precondition, and uses process argv plus stdin
without a shell. It invokes `bd --sandbox --actor <safe-actor> -C <configured
repo> ... --json`. The safe actor contains opaque Campsite ids, not names,
emails, tokens, or channel text.

An inbound callback into a repository host was rejected because it adds
reachability, webhook-secret, and SSRF problems. Rails-side command execution
was rejected for the same repository-custody reasons as the read proposal.

### A-15 — Command leases serialize writes without claiming exactly once

An operation moves through Pending, Claimed, Succeeded, Failed, Conflict,
Expired, Cancelled, or Unknown. Claim sets an opaque attempt id and short lease;
only the exact connector and attempt can complete it. One source has at most one
active mutation lease. Pending work can be cancelled; claimed work can only be
marked cancellation-requested because the local process can already have run.

Expired leases do not trigger an automatic write retry. The next executor first
runs the action's reconciliation read. If it proves the desired mutation
already exists, it returns a reconciled success receipt. If it proves no
mutation occurred, it MAY claim a new attempt. If neither is provable, the
operation becomes Unknown for human resolution.

### A-16 — Source revisions prevent stale automation, with narrow rebase rules

Every operation records the snapshot revision on which it was drafted. Before
mutation, the executor compares that precondition with `bd vc status`. Create
MAY proceed across an unrelated revision only after its idempotency lookup and
target parent/dependency validation still succeed; the receipt records the
rebased revision. Update, claim, close/reopen, and dependency actions conflict
on a changed target `updated_at`, status, or dependency set and do not guess.

The API/UI returns a structured conflict containing only safe current snapshot
fields and offers re-draft/re-confirm. It never asks the executor to reset,
checkout, merge, or overwrite Beads history.

### A-17 — Campsite operation metadata makes create retries reconcilable

Before create, the executor searches for exact metadata
`campsite_operation_id=<opaque-operation-id>` including closed issues. If one
regular issue exists, it verifies the intended immutable fields and returns its
id as reconciled success. If none exists, it invokes `bd create` with that
metadata marker and structured fields. If more than one or a mismatched issue
exists, it returns Conflict/Unknown and creates nothing.

The marker is integration provenance, not authorization or task truth. The
read-only snapshot strips metadata, and the normal Board serializer never
exposes it. Existing `external_ref` remains available for GitHub/Jira/Linear
links and SHALL NOT be commandeered for idempotency.

For update-like actions, the executor reads the target before and after. Native
idempotent semantics MAY return reconciled success only when the desired state
is exact; otherwise an ambiguous timeout becomes Unknown rather than a blind
repeat.

### A-18 — Receipts prove execution; snapshots remain the Board projection

The executor completion contains operation/attempt ids, safe action kind,
source revision before and after, target/result issue id, normalized before/
after summaries needed for verification, exit classification, and timestamps.
It does not return the repository path, environment, token, raw command line,
raw stdout/stderr, stack trace, or excluded Beads fields.

Succeeded is set only after the executor parses a valid native `bd --json`
result and verifies the postcondition with a read. It then publishes a fresh
atomic Board snapshot. Until that snapshot becomes current, the operation UI
says **Applied; Board refresh pending** and the card remains in its prior
column. A failed snapshot publication does not change a proven operation
receipt, and a successful receipt does not fabricate a snapshot.

### A-19 — AI drafts are untrusted, reviewable, and disclosure-bounded

The native **Draft with AI** flow takes a user instruction plus an explicit,
bounded selection of channel objects. Server-side retrieval rechecks access to
each object; the client cannot submit hidden content by id. The model receives
only the selected safe text and current allowlisted Board metadata needed to
find possible duplicates/parents/dependencies. Attachments and linked external
pages are excluded unless separately specified.

The model returns structured draft fields and citations, never a CLI command.
Deterministic validation runs after inference. The review shows target channel,
Beads source display name/project id, repository-audience warning, every field
that will be written, selected citations, and the current source revision.
Editing the draft invalidates an earlier approval digest.

Duplicate suggestions are advisory. AI SHALL present likely matching current
Beads but SHALL NOT silently merge, update, close, or suppress a requested
create. Prompt text, channel content, Beads titles, and model output are all
untrusted data and cannot change the action grant or executor configuration.

### A-20 — MCP exposes bounded tools, not an AI-specific bypass

Add read tools for the current Board/source freshness and write tools
`create_bead`, `update_bead`, `claim_bead`, `close_bead`, `reopen_bead`,
`add_bead_dependency`, and `remove_bead_dependency`. Each write tool requires
`mcp`, `write_beads`, the matching source action grant, the resource owner's
`operate_beads?` policy, and the same operation schema/preconditions as REST.

Tool results return a pending operation and approval requirement, or a final
receipt if the client explicitly waits within a bounded interval. They never
claim success merely because a command was queued. `tools/list` descriptions
name the external repository mutation and expected confirmation accurately.

Campsite's MCP server continues to perform no inference. Any compatible agent
can reason over the tools. The native AI drafting endpoint uses the same domain
schema, keeping model/provider choice separate from mutation safety.

### A-21 — Cross-boundary content and audit retention are explicit

By default, operations write only fields visible in the final preview. A source
MAY disallow descriptions, notes, design, acceptance criteria, or citations
entirely. No hidden conversation history, system prompt, model reasoning,
credential, user email, private attachment URL, or OAuth data is persisted to
Beads or the receipt.

Campsite retains operation request, normalized payload digest, approvals,
actor/application ids, state transitions, safe receipt, and source revisions
under a documented retention period that remains an open implementation
decision. Raw model prompts/responses SHALL NOT be retained by this feature
unless Campsite's existing AI privacy contract explicitly requires it; any such
retention is shown before use.

### A-22 — Channel/source lifecycle fails closed

Archive, source replacement/detach, connector detachment, grant revocation,
token revocation, or feature-flag disablement stops new claim and execution.
Pending operations are cancelled or expired with an audit reason. Claimed
operations become cancellation-requested and reconcile before any retry.

Deleting cached Campsite operations never issues a compensating Beads command.
Undo is an explicit new operation (for example reopen after close) with current
authorization and revision checks, not a rollback of external history.

## Risks / Trade-offs

- **RISK-8 — Private Campsite content leaks into a more widely readable
  repository.** → Require explicit source/audience preview, selected context,
  field allowlists, approval-digest invalidation, and no hidden context copy.
- **RISK-9 — Prompt injection asks an agent to exceed its grant.** → Treat all
  content/model output as data; server authorization and executor command
  allowlists run after inference and never accept shell/flags/path input.
- **RISK-10 — A timeout duplicates a create.** → Persist an opaque operation id
  in Beads metadata, reconcile by exact metadata before retry, and mark
  ambiguous/multiple matches Unknown.
- **RISK-11 — Stale snapshots cause an incorrect update or close.** → Carry
  source and target preconditions, allow only a narrow validated create rebase,
  and return structured conflicts without force flags.
- **RISK-12 — An OAuth app is labeled Agent and gains unintended repository
  writes.** → Separate descriptive classification, `write_beads` consent,
  initiating-user policy, and per-source action/autonomy grants.
- **RISK-13 — Concurrent agents contend for embedded Dolt.** → One active source
  lease, bounded execution, native lock errors as retryable pre-execution only,
  and no parallel local mutations.
- **RISK-14 — A successful queue response is mistaken for a successful task
  mutation.** → Distinct operation states, verified executor receipt, and Board
  refresh pending state; no optimistic card changes.
- **RISK-15 — Executor authority silently expands to remote sync or code
  changes.** → Exact command/action allowlist, `--sandbox`, no raw flags or
  shell, no Git/Dolt commands, and contract tests that snapshot process argv and
  filesystem/Git/remote state.
- **RISK-16 — Audit data itself exposes secrets or local topology.** → Store
  structured safe classifications and opaque ids; redact raw process output,
  repository paths, emails, tokens, environment, and model hidden context.

## Migration Plan

1. Obtain an explicit stewardship-policy change and complete/verify
   `add-channel-beads-board`; create an isolated worktree from the user-named
   integration branch.
2. Add feature-flagged operation/grant persistence, policies, `write_beads`
   scope, queue/lease endpoints, redacted receipt schema, and source lifecycle
   cancellation without enabling execution.
3. Extend the disposable-fixture publisher with source-bound executor mode;
   enable only `create`, verify metadata reconciliation and fresh snapshot
   publication, then complete security and failure-injection tests.
4. Add the human New Bead form and exact disclosure/approval/status UI. Trial
   create-only against a private disposable channel/repository with no remote
   sync.
5. Add AI draft generation and MCP Board/create tools in `suggest_only`, then
   approval-required mode. Verify prompt injection, cross-audience disclosure,
   OAuth/Pundit denial, and provider logging behavior.
6. Enable update, claim, close/reopen, and dependency operations one at a time
   only after each action's precondition, reconciliation, audit, tests, and UAT
   pass. Keep bounded-autonomous mode disabled until separately approved.
7. Roll back by disabling the operation feature and stopping executor claims.
   Preserve external Beads history; cancel pending commands and reconcile any
   claimed command rather than issuing compensating writes.

## Open Questions

- What existing Campsite role receives `operate_beads?`, or do source
  managers maintain a separate human operator list?
- Which native AI provider/model and retention controls power Draft with
  AI when implementation is authorized?
- What operation/audit retention period is appropriate?
- Should bounded-autonomous mode be part of the first release, or remain
  specified but disabled until human-confirmed usage provides evidence?
- Should source context be stored in Beads as approved text, Campsite links, or
  neither by default?
