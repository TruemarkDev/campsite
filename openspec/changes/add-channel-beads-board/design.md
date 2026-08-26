## Context

See `proposal.md` for motivation and the stewardship gate.

The existing project UI already has the composition point this change needs:
`apps/web/components/Projects/ProjectView.tsx` renders Posts or Chat, Docs, and
Calls from three Next.js routes. It also owns the view buttons and numeric
hotkeys. Chat-format projects omit Docs and currently use a reduced Chat/Calls
set. Project-route recognition is also duplicated in NavigationBar and
split-view hooks, so adding only the page and buttons would leave mobile or
detail behavior inconsistent.

Projects already attach organization-owned OAuth applications through
`ProjectMembership`. `Project#add_oauth_application!` also attaches the app to a
chat project's message thread. The management endpoint intentionally requires
`ProjectPolicy#manage_integrations?`, so its full `OauthApplicationSerializer`
is not an appropriate roster response for ordinary channel viewers.
Channel data export currently covers channel metadata, posts, docs, and calls;
it has no external-task-content contract.

There is no Beads integration in Rails or the web app. Beads 1.2.2 is installed
from Homebrew/core at `/opt/homebrew/bin/bd`; Homebrew reports 1.2.2 as the
latest stable release as of 2026-08-26. Its supported local-first boundary is
the CLI and Dolt remote workflow. `bd export` is for interoperability, while
the Dolt database, branches, working set, and remote are Beads-owned state. The
installed CLI has no supported `bd serve` contract on which this application
can depend.

Beads has no per-issue access control or at-rest encryption. Its default export
also contains descriptions, notes, design text, acceptance criteria, comments,
and dependency metadata that the Board does not need. The integration therefore
needs an explicit disclosure boundary rather than mirroring the export payload.

The system also has no liveness signal for OAuth applications. Attachment to a
project proves authorization and routing, not that an agent process is online.

## Goals / Non-Goals

**Goals:**

- Preserve Beads as the only task authority while making its current task state
  visible to channel members.
- Reuse explicit project and OAuth application memberships, with a Board read
  policy narrower than public-channel `show?`, instead of creating an unrelated
  ACL store.
- Decouple Campsite from Beads' Dolt schema and local repository layout through
  a small, versioned snapshot protocol.
- Make source revision, collection time, and last successful ingest visible so
  users can judge freshness without an invented sync SLA.
- Reuse the existing attached-application model for a credential-free agent
  roster, with an explicit agent classification and honest presence language.
- Keep the first slice additive, feature-flagged, dependency-free, and
  reversible without writing to or migrating a Beads database.

**Non-Goals:**

- Dragging cards, editing task fields, claiming, closing, or otherwise writing
  from Campsite back to Beads.
- Direct Rails access to a repository checkout, `.beads` directory, Dolt SQL
  server, Dolt remote, or Beads credentials.
- Importing Beads memories, infrastructure records, agent messages, comments,
  notes, design text, acceptance criteria, or repository paths.
- Live agent presence, job dispatch, capacity scheduling, or automatic work
  assignment.
- Multiple Beads sources per channel, cross-channel aggregation, or a generic
  multi-tracker abstraction in the first slice.
- A Campsite-owned scheduler. Publication cadence belongs to the repository-side
  automation and is reported, not promised, by Campsite.

## Decisions

### A-1 — Board is an additive project route owned by `ProjectView`

Add `/[org]/projects/[projectId]/board.tsx` using the same provider, project
fetching, 404, title, split-view, and sidebar patterns as the existing routes.
`ProjectView` appends **Board** after Calls and renders the Board component when
that route is active.

Post channels use shortcuts 1 Posts, 2 Docs, 3 Calls, 4 Board. Chat channels
preserve their current 1 Chat and 2 Calls shortcuts and use 3 Board. Preserving
existing chat shortcuts is less surprising than reserving an invisible Docs
slot solely to make Board use 4. On narrow screens the view buttons remain in
their existing titlebar composition but SHALL scroll or collapse without
truncating the active view.

The Board route exists even before a source is attached. Explicit project
members receive a neutral empty state; members with `manage_integrations?` also
receive the setup affordance. Organization members who can see a public channel
only through `view-any` permission do not see or read its Board. Hiding the
route from every unattached channel was rejected because it makes the capability
hard to discover and creates route/navigation races after detach.

Add Board to the existing NavigationBar and split-view route predicates as a
new route only. Calls' current omissions or inconsistencies are unrelated and
SHALL NOT be silently changed in this feature.

### A-2 — One project source is bound to one attached OAuth application

Add a `ProjectBeadsSource` with a unique `project_id`, opaque public id,
Beads-reported `source_project_id`, display name, connector
`oauth_application_id`, current snapshot reference, and successful-ingest
metadata. The connector application SHALL belong to the organization and SHALL
remain attached to the project through the existing `ProjectMembership`
relationship.

Human source create/update/destroy actions use the existing
`manage_integrations?` policy. Snapshot ingest accepts an OAuth application
actor only when it matches the source's connector application and is still
attached to that project. Board reads use a new policy that requires a kept
human or OAuth-application project membership; broad `show?` permission for a
public channel is insufficient. An explicitly attached guest can read the same
allowlisted Board metadata as other project members but cannot configure it.
This prevents an attached private repository's task names from inheriting a
broader organization-wide public-channel audience by accident.

This reuses existing credential issuance and revocation. A new source-specific
secret was rejected because it would duplicate OAuth token custody and create a
second rotation path.

### A-3 — The repository publishes a normalized read-only snapshot

The repository-side publisher invokes the configured `bd` binary with
`--readonly` and `-C <repo>` and collects only first-party outputs:

- `bd context --json` for opaque project identity and compatibility metadata;
- `bd vc status --json` for the Dolt branch/revision;
- `bd export` for regular issue records (without `--all`,
  `--include-infra`, or `--include-memories`);
- `bd ready --json` and `bd blocked --json` for Beads-native dependency
  classification.

Before transport, the publisher reduces each issue to snapshot schema v1:
external id, title, status, board state, priority, issue type, assignee/owner
display strings, labels, parent id, created/updated/closed timestamps, and safe
dependency ids/types needed for display. It strips descriptions, notes, design,
acceptance criteria, comments, actor audit text, filesystem paths, database
configuration, and credentials. The repository path is used only as the local
CLI working directory and is never part of the request.

The publisher computes a digest over the normalized payload and submits the
Beads revision, Beads CLI/schema metadata, collection timestamp, digest, and
issues to Campsite. Campsite owns and versions this transport schema; it does
not deserialize Beads database rows or promise compatibility with internal Dolt
tables.

A Rails-side puller, direct Dolt connection, and request-time shell execution
were rejected because they put repository or database custody in the web tier,
couple deployments to Beads internals, and turn board reads into operational
side effects.

### A-4 — Immutable snapshots make ingest atomic and idempotent

Persist validated payloads as immutable `ProjectBeadsSnapshot` records keyed by
source plus digest/revision. A transaction creates the snapshot and advances the
source's current-snapshot pointer. Repeating the same digest returns the current
snapshot without duplicating records or emitting duplicate invalidations.

The endpoint validates the protocol version, source id, recognized primitive
types, unique issue ids, coherent Ready/Blocked classifications, timestamps,
and bounded request/card field sizes before changing the current pointer. A
rejected or interrupted upload leaves the last successful snapshot visible. An
accepted older collection timestamp is retained for audit only and cannot
replace a newer current snapshot.

The API returns one current snapshot rather than exposing snapshot history to
the web UI. Retention is operational cleanup, not user-facing task history;
Beads remains the audit source.

### A-5 — Board state comes from Beads commands, not duplicated graph logic

The publisher assigns mutually exclusive columns with this precedence:

1. `status == closed` → Closed;
2. id reported by `bd blocked --json` → Blocked;
3. `status == in_progress` → In progress;
4. id reported by `bd ready --json` → Ready.

For an open issue, membership in Ready and Blocked SHALL be exclusive and one of
them SHALL be present. Inconsistent input is rejected instead of guessed. This
uses Beads' native dependency semantics rather than reimplementing blocker
resolution in Rails or TypeScript.

Closed work is paged or progressively revealed so a long project history does
not swamp active work. Filtering by title/id, type, priority, assignee, label,
and inclusion of Closed is client-visible behavior; the exact layout and page
size remain implementation details.

### A-6 — Agent classification is explicit; availability is not inferred

Add an `agent_capable` boolean to `OauthApplication`, defaulting to false, and
an organization-admin setting to classify an integration as an agent. The
Board roster reads only agent-capable applications attached through the
project's kept memberships. If the source connector is also agent-capable, its
safe projection carries both **Agent** and **Beads publisher** roles; a
publisher-only app appears separately as **Beads publisher**.

The roster serializer exposes only public id, name, avatar URLs, and channel
roles. It uses the Board's explicit-membership read policy and never reuses the
full integration-management serializer, which also contains redirect, webhook,
client, and secret-oriented fields. Every entry is labeled **Attached**. No
timestamp or token activity is converted into Online, Idle, or Offline because
OAuth token use is not an agent heartbeat.

Inferring agents from `provider == mcp_cimd` was rejected: CIMD identifies a
client-registration mechanism, not a one-agent identity, and generic OAuth MCP
clients would be missed.

### A-7 — Snapshot acceptance invalidates the existing web query path

The API follows existing Apigen controller/Blueprinter patterns. After accepting
a new current snapshot, it emits one project-scoped stale event through the
existing Pusher job pattern. The web hook invalidates the current Board query;
it does not merge cards optimistically because the snapshot is authoritative as
a unit.

Project serializer changes are limited to a source-present capability flag if
the navigation needs it. Full Board data stays on a dedicated endpoint to avoid
inflating every project response. `script/gen-client` regenerates the TypeScript
client after API metadata changes.

### A-8 — The first Board is deliberately read-only

Cards are not draggable and no task mutation endpoint is exposed. A future
write design would need a connector command channel, Beads revision preconditions,
per-operation authorization, conflict/error receipts, and exact proof that a
`bd` command succeeded before updating the snapshot. Treating a local UI move
as task truth would create split-brain state, so it is outside this change.

### A-9 — Detach, archive, delete, and export preserve external custody

Detaching a source deletes its cached Campsite snapshots after confirmation and
revokes that source binding; it does not call Beads. Deleting a channel removes
the source and cached snapshots through ordinary dependent cleanup. Archiving a
channel preserves the last snapshot for authorized readers but rejects new
ingest until the channel is unarchived, avoiding background churn for frozen
spaces.

Channel data export does not include the Beads source, snapshot cards, or agent
roster in v1. Those external records have a narrower explicit-membership policy
than ordinary public channel content, and silently adding them to an existing
export would widen disclosure. A later export contract can opt in with an
explicit warning and authorization review.

## Risks / Trade-offs

- **RISK-1 — A channel can have a broader audience than the repository's Beads
  database.** → Source setup shows the exact channel visibility and the
  allowlisted fields before confirmation; only a member with integration
  management permission can attach it, and Board reads require explicit kept
  project membership rather than public-channel `view-any` access.
- **RISK-2 — Issue titles and labels are untrusted external text.** → Validate
  length/encoding, serialize as data, and render as text without HTML or
  executable links.
- **RISK-3 — A publisher stops running and the Board looks current.** → Always
  show source revision and last successful collection/ingest times; do not
  invent an Online or freshness SLA. The previous snapshot remains readable.
- **RISK-4 — Beads CLI output changes.** → Parse into a versioned Campsite
  snapshot locally, fail closed on missing/invalid fields, and keep the previous
  snapshot. Never bind Rails to Beads' Dolt schema.
- **RISK-5 — Large closed histories increase storage and client work.** → Bound
  accepted payloads, page/progressively reveal Closed cards, and prune old
  immutable snapshots while retaining the current one.
- **RISK-6 — `agent_capable` is manually misclassified.** → Default false,
  restrict changes to organization integration managers, and describe the value
  as classification rather than verified runtime behavior.
- **RISK-7 — Existing dirty work overlaps future implementation files.** → Use a
  clean, isolated feature worktree after stewardship approval; do not implement
  in the currently dirty `main` checkout.

## Migration Plan

1. Change stewardship policy explicitly before implementation. Create an
   isolated worktree from the named integration branch; do not absorb the
   current checkout's unrelated API, web, deployment, lockfile, or Beads-export
   changes.
2. Add the nullable/additive source and snapshot tables plus the default-false
   OAuth application classification. Run schema load/migration tests; no
   existing channel or integration requires a backfill.
3. Add source management, safe roster, Board read, and authenticated snapshot
   ingest contracts behind a disabled `channel_beads_board` feature flag,
   including archive/detach/delete cleanup and export exclusion tests.
4. Regenerate the API client, then add the web route/navigation, empty state,
   NavigationBar/split-view route recognition, read-only Board, roster,
   filtering, and stale-query handling.
5. Deliver and contract-test the repository-side publisher against a fixture
   Beads workspace using the installed `bd --readonly` commands. Document its
   source, version/update command, bare-environment PATH, OAuth token custody,
   and operator-selected publication trigger.
6. Enable the flag for one private test channel, attach one source, publish a
   known snapshot, and complete desktop/mobile authorization and failure UAT
   before broader enablement.
7. Roll back by disabling the feature flag. This hides setup/navigation and
   blocks new ingest while leaving Beads untouched. Source/snapshot deletion is
   a separate explicit cleanup action, not part of rollback.
