## Purpose

Expose a channel's project work as a source-faithful, read-only Beads Board
without transferring task authority, repository access, or Beads credentials to
Campsite.

## ADDED Requirements

### Requirement: SyR-1 — Channel managers can attach one Beads source

The system SHALL allow a member authorized to manage a channel's integrations
to attach, replace, or detach one Beads source for that channel. The attachment
SHALL identify the source by an opaque project id and display name and SHALL bind
it to one OAuth application already attached to the channel.

**Verification:** Test

#### Scenario: Manager attaches a source

- **WHEN** a channel integration manager selects an attached OAuth application
  and submits an opaque Beads project id and display name
- **THEN** the channel has one Beads source and its Board can accept snapshots
  only from that application

#### Scenario: Ordinary viewer cannot change the source

- **WHEN** a member who can view the channel but cannot manage its integrations
  attempts to attach, replace, or detach a source
- **THEN** the system rejects the action without changing the existing source

#### Scenario: Connector application is no longer attached

- **WHEN** the OAuth application bound to the source is removed from the channel
- **THEN** subsequent snapshot publication by that application is rejected and
  the last successful snapshot remains read-only

#### Scenario: Source is detached

- **WHEN** an authorized manager detaches the Beads source
- **THEN** the Board returns to its unattached empty state, cached Campsite
  snapshots for that binding are deleted, and no Beads database or repository
  data is modified

### Requirement: SyR-2 — Snapshot ingest is authenticated, versioned, and atomic

The system SHALL accept a versioned, normalized snapshot only from the source's
bound OAuth application. It SHALL validate the full snapshot before making it
current, SHALL make repeated publication of the same digest idempotent, and
SHALL retain the last successful snapshot when a new payload is rejected or
interrupted.

**Verification:** Test

#### Scenario: Bound publisher submits a valid snapshot

- **WHEN** the source's bound OAuth application submits a supported snapshot
  containing the matching source id, revision, digest, collection time, and
  coherent issue records
- **THEN** the snapshot becomes current atomically and channel Board readers are
  notified that their query is stale

#### Scenario: Another application submits a snapshot

- **WHEN** a different OAuth application submits a snapshot for the channel
- **THEN** the system rejects the request and does not reveal or replace the
  current snapshot

#### Scenario: Snapshot is invalid

- **WHEN** an authenticated publisher submits an unsupported schema version,
  duplicate issue ids, invalid primitive fields, or incoherent Board states
- **THEN** the system rejects the entire payload and continues serving the last
  successful snapshot

#### Scenario: Snapshot is repeated

- **WHEN** the publisher resubmits the current source revision and digest
- **THEN** the system returns the existing accepted result without duplicating
  a snapshot or emitting a duplicate stale event

#### Scenario: Older collection arrives after a newer snapshot

- **WHEN** a valid snapshot has a collection time older than the current
  snapshot
- **THEN** the system SHALL NOT replace the current snapshot with the older one

### Requirement: SyR-2a — Board visibility requires explicit channel membership

The system SHALL authorize Board, source-summary, snapshot, and roster reads
only for a kept human or OAuth-application membership on the channel. Broad
organization permission to view a non-private channel SHALL NOT reveal whether
a Beads source exists or any task or agent metadata. An explicitly attached
guest MAY read the allowlisted Board but SHALL NOT configure it.

**Verification:** Test

#### Scenario: Explicit project member reads a Board

- **WHEN** a kept channel member requests its current Board snapshot
- **THEN** the system returns the safe Board response permitted for that channel

#### Scenario: Organization member can view public posts but is not attached

- **WHEN** an organization member can view a public channel through a broad role
  permission but has no kept membership on that channel
- **THEN** the system rejects the Board request without revealing source,
  snapshot, issue, or roster metadata

#### Scenario: Explicit guest reads a Board

- **WHEN** a guest has a kept membership on the channel and requests its Board
- **THEN** the system returns the same allowlisted task metadata while omitting
  source-management controls

### Requirement: SyR-3 — Beads remains the sole task authority

The system SHALL present the Board as read-only and SHALL NOT execute Beads
commands, access repository paths, connect to Dolt, or mutate a task from a web
request or background job. The Board SHALL identify the Beads source revision
and last successful collection time represented by its cards.

**Verification:** Inspection + Test

#### Scenario: Viewer opens a task card

- **WHEN** a channel member opens or filters a Board card
- **THEN** the system displays snapshot metadata without offering drag, claim,
  edit, close, dependency mutation, or other task-write controls

#### Scenario: Board is read

- **WHEN** a user loads the Board route
- **THEN** the request is served from the accepted Campsite snapshot and does
  not access a repository, Beads CLI, Beads database, or Dolt remote

#### Scenario: Snapshot identifies its authority

- **WHEN** a snapshot is present
- **THEN** the Board displays its source name, Beads revision, and last
  successful collection time

### Requirement: SyR-4 — Board columns preserve Beads state

The system SHALL display Ready, In progress, Blocked, and Closed columns using
the mutually exclusive state classification supplied by the publisher. Closed
status SHALL take precedence, followed by Beads' blocked classification,
in-progress status, and Beads' ready classification. The ingest contract SHALL
reject an open issue that is neither Ready nor Blocked or is classified as both.

**Verification:** Test

#### Scenario: Ready issue is displayed

- **WHEN** an open issue is reported by Beads as ready and not blocked
- **THEN** the Board displays it in Ready with its source status unchanged

#### Scenario: Blocked issue is displayed

- **WHEN** an open issue is reported by Beads as blocked
- **THEN** the Board displays it in Blocked and shows safe blocker identifiers
  supplied by the snapshot

#### Scenario: In-progress issue is displayed

- **WHEN** an issue has Beads status `in_progress` and is not reported blocked
- **THEN** the Board displays it in In progress

#### Scenario: Closed issue is displayed

- **WHEN** an issue has Beads status `closed`
- **THEN** the Board displays it in Closed regardless of historical dependency
  metadata

#### Scenario: State classifications conflict

- **WHEN** an open issue appears in both the Ready and Blocked classifications
  or in neither classification
- **THEN** the snapshot is rejected instead of guessing a Board column

### Requirement: SyR-5 — Channel Board is the view after Calls

The system SHALL expose a Board route through the existing channel view
switcher. A post channel SHALL show Posts, Docs, Calls, and Board in that order;
a chat channel SHALL preserve Chat and Calls and append Board. Existing view
shortcuts SHALL remain stable, with Board using 4 for post channels and 3 for
chat channels.

**Verification:** Demonstration + Test

#### Scenario: Post channel navigation

- **WHEN** a member views an ordinary post channel
- **THEN** Board is the fourth view after Calls and shortcut 4 opens it

#### Scenario: Chat channel navigation

- **WHEN** a member views a chat-format channel
- **THEN** Board appears after Calls, Chat remains shortcut 1, Calls remains
  shortcut 2, and Board uses shortcut 3

#### Scenario: Channel has no source

- **WHEN** a member opens Board before a Beads source is attached
- **THEN** the route shows a neutral unattached state and shows setup controls
  only to a member authorized to manage integrations

#### Scenario: Board is opened on a narrow viewport

- **WHEN** the channel view switcher cannot fit at mobile width
- **THEN** all available views remain reachable and the active Board view
  remains identifiable without obscuring channel details controls

### Requirement: SyR-6 — Board exposes only allowlisted task metadata

The snapshot contract SHALL accept only task id, title, source status, Board
state, priority, issue type, assignee/owner display strings, labels, parent id,
safe dependency ids/types, and task timestamps. It SHALL NOT accept Beads
memories, infrastructure records, agent messages, comments, descriptions,
notes, design text, acceptance criteria, repository paths, database
configuration, remote URLs, or credentials. All accepted text SHALL be rendered
as plain text.

**Verification:** Inspection + Test

#### Scenario: Publisher sends the allowlisted record

- **WHEN** the publisher reduces a regular Beads issue to snapshot schema v1
- **THEN** the request contains only allowlisted fields and the Board can render
  the card without loading any original Beads content

#### Scenario: Payload includes a forbidden field

- **WHEN** a snapshot contains a repository path, note, comment, memory,
  infrastructure record, credential, or other field outside the allowlist
- **THEN** the system rejects or strips that field according to the schema and
  never returns it to a Board viewer

#### Scenario: Task title contains markup

- **WHEN** an issue title or label contains HTML, Markdown, an ANSI sequence, or
  control characters
- **THEN** the Board displays sanitized plain text and does not create an
  executable link or markup node from that content

### Requirement: SyR-7 — Snapshot freshness and failure are explicit

The system SHALL expose the current snapshot's Beads revision, collection time,
and successful ingest time. It SHALL keep the last successful snapshot visible
after a failed ingest and SHALL distinguish an unattached source, an attached
source with no successful snapshot, and a source with a current snapshot. It
SHALL NOT claim a synchronization SLA that the publisher has not established.

**Verification:** Test

#### Scenario: Source has never published

- **WHEN** a source is attached but has no successful snapshot
- **THEN** the Board shows a waiting-for-first-sync state rather than an empty
  task list

#### Scenario: New ingest is rejected

- **WHEN** a source already has a successful snapshot and its next ingest is
  rejected
- **THEN** the Board continues showing the previous cards and their original
  revision and timestamps

#### Scenario: Viewer checks freshness

- **WHEN** a current snapshot is displayed
- **THEN** the viewer can inspect its exact revision, collection time, and
  ingest time without an unsupported Online or up-to-date claim

### Requirement: SyR-8 — Board filtering does not alter source state

The system SHALL allow a viewer to filter the current snapshot by task id or
title, issue type, priority, assignee, label, and inclusion of Closed work. A
filter SHALL affect only the viewer's rendered result and SHALL NOT mutate the
snapshot or Beads.

**Verification:** Test

#### Scenario: Viewer filters active work

- **WHEN** a viewer selects one or more supported filters
- **THEN** each Board column displays only matching cards and the unfiltered
  snapshot remains unchanged

#### Scenario: Viewer includes closed work

- **WHEN** a viewer enables Closed work for a source with a long history
- **THEN** matching closed cards are progressively available without hiding or
  reclassifying active cards

### Requirement: SyR-8a — Channel lifecycle does not mutate Beads or widen exports

The system SHALL stop accepting new snapshots while a channel is archived,
SHALL preserve its last successful snapshot for explicitly attached readers,
and SHALL resume ingest only after unarchive. Detach or channel deletion SHALL
remove cached Campsite snapshots without contacting Beads. Existing channel
data exports SHALL NOT include Beads source metadata, cached task cards, or the
agent roster.

**Verification:** Test

#### Scenario: Channel is archived

- **WHEN** a channel with a current Board snapshot is archived
- **THEN** attached readers can inspect the preserved snapshot and the publisher
  cannot replace it until the channel is unarchived

#### Scenario: Channel is deleted

- **WHEN** a channel with a Beads source is deleted
- **THEN** its source binding and cached snapshots are deleted without a request
  to the external Beads workspace

#### Scenario: Member exports channel data

- **WHEN** a member requests the existing channel data export
- **THEN** the export excludes the Beads connection, cached issue metadata, and
  channel agent roster
