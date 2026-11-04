## Why

Campsite channels already collect a project's posts, docs, calls, chat, and
attached integrations, while the project's executable work remains in a
separate Beads database. This proposal makes that work visible in its channel
without moving task custody out of Beads or giving the web application access
to repository files.

❌ **Unbuilt:** `MAINTENANCE.md` currently forbids new product features. This
change records the contract and implementation plan; product work SHALL NOT
start unless stewardship policy is explicitly changed.

## What Changes

- A confirmed, explicitly attached channel member with permission to manage
  integrations can connect one Beads repository from Channel details. A
  short-lived pairing challenge completed inside that repository proves control
  of the target Beads workspace; Campsite never stores or receives its local
  path, Dolt credentials, database, or reusable repository credential.
- A repository-side publisher uses Beads' read-only CLI commands to send an
  allowlisted, versioned snapshot to Campsite. Beads remains authoritative and
  the first slice does not write task changes back to Beads.
- A verified connection enables the **Board** view after Calls. Unconnected or
  still-unverified channels do not advertise the route. On ordinary post
  channels Board is the fourth view beside Posts, Docs, and Calls; chat-format
  channels retain their existing reduced view set and append Board after Calls.
- The Board presents Ready, In progress, Blocked, and Closed work using state
  classifications reported by Beads, with filtering and explicit snapshot
  revision/freshness information.
- The Board includes a safe roster of OAuth applications attached to the
  channel. It distinguishes the Beads publisher from agent-capable apps and
  says **Attached**, not **Online**, because the current system has no agent
  heartbeat or presence contract.
- Board cards render task metadata as plain text. The publisher excludes Beads
  memories, infrastructure records, comments, notes, design text, and local
  paths from the initial snapshot contract.
- No new runtime dependency is introduced. The publisher targets the installed
  Homebrew `bd` binary's stable read commands and a Campsite-owned snapshot
  schema rather than a Beads database schema.
- The source contract retains the opaque source id, connector identity, exact
  Dolt revision, and protocol seams needed by the separately specified
  `add-ai-beads-operations` follow-up. This change remains read-only and exposes
  no task mutation endpoint.

## Capabilities

### New Capabilities

- `channel-beads-board`: channel source attachment, authorized snapshot ingest,
  source-faithful board state, filtering, empty/error states, and fourth-view
  navigation.
- `channel-agent-roster`: safe display of channel-attached agent-capable OAuth
  applications without exposing integration credentials or claiming live
  availability.

### Modified Capabilities

- None. This repository has no archived baseline specs yet.

## Impact

- **Rails API:** additive project/source/snapshot persistence, source management
  and ingest endpoints, project authorization, serializers, and generated API
  schema.
- **Web:** a Channel-details Beads connection section, short-lived pairing UI,
  a conditionally enabled project Board route, `ProjectView` navigation/hotkeys,
  query hooks, board/empty/error UI, mobile behavior, and agent roster.
- **External boundary:** a repository-side publisher calls `bd --readonly`
  (`context`, `vc status`, `export`, `ready`, and `blocked`) and submits only the
  normalized snapshot. Campsite does not connect to Dolt and does not execute
  `bd` in request or job processes.
- **Generated client:** `script/gen-client` updates
  `packages/types/generated.ts`; the generated file SHALL NOT be hand-edited.
- **Testing and release:** Rails model/controller tests, web component/hook
  tests, API codegen verification, browser/mobile UAT, publisher contract tests,
  and a rollback that detaches or hides the Board without modifying Beads.
- **Dependencies:** none. Beads 1.2.2 is currently installed from
  Homebrew/core and is the latest stable Homebrew release as of 2026-08-26;
  compatibility is through the normalized snapshot protocol, not a pinned
  internal database schema.
- **Tracking:** Beads issue `campsite-4cl` remains open for this unbuilt feature;
  child `campsite-4cl.1` tracks the separately gated AI/write follow-up.
