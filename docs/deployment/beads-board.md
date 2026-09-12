# Beads Board operator guide

The authoritative product contract is
[add-channel-beads-board](../../openspec/changes/add-channel-beads-board/README.md).
Its specifications take precedence over this operational guide. AI task writes
are a separate proposal and are not implemented by this integration.

The review implementation is in `campsite-wt-beads-board`, on
`codex/beads-board-current-base`, based on `976b2b7eebb8d31feaabcc8961f4f2242be5416e`.
Prakash reauthorized completion on 2026-09-12 as a stewardship exception, with
the result retained in that worktree. This is not deployment approval.

## What runs where

The repository-side `script/publish-beads-board` is a dependency-free Ruby
program. It runs `bd --readonly` in the selected repository and sends an
allowlisted snapshot to the Rails API. Rails and Sidekiq do not run Beads or
open its repository or Dolt database. The web app reads accepted snapshots from
Rails; it never writes tasks back to Beads.

Publication reads `context --json`, `vc status --json`, `export`,
`ready --json --limit 0`, and `blocked --json`. Identity and revision are read
again before publication so a changed source fails collection. The normal
`export` command excludes Beads memories and infrastructure records. The
publisher additionally removes descriptions, notes, comments, design text, and
other fields outside the snapshot schema. Unknown or conflicting issue states
fail collection rather than being assigned a guessed column.

Accepted snapshots are immutable through normal model updates. Identical
digests are idempotent; older collections remain audit records without moving
the current pointer. A current-pointer advance sends the project id to the
private user channels of its kept human members. The web invalidates the whole
Board query. No organization-wide Board event is broadcast.

## Local requirements and updates

On 2026-09-12, Homebrew reported both installed and stable Beads as **1.2.2**.
The official source is [gastownhall/beads](https://github.com/gastownhall/beads),
and this installation comes from Homebrew/core. Its update command is
`HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade beads` after refreshing and reviewing the
available version through the normal tool maintenance workflow.

The publisher was verified with Ruby 4.0.6 and `/opt/homebrew/bin/bd`. A bare
`PATH=/opt/homebrew/bin:/usr/bin:/bin` resolves the installed Ruby and Beads on
this Mac. A shell profile is not required. Other machines need their Ruby and
Beads directories in the process environment explicitly. The publisher is kept
in this repository; it has not been installed as a global CLI or daemon.

`bd context` rejects some temporary-directory repository locations. Use a
normal repository directory for a disposable integration fixture. Always
resolve the selected workspace's opaque `project_id` through `bd context`;
do not infer it from a directory or Git remote name.

## Pair and publish

Enable `channel_beads_board` for the target organization only after its API
and web rollout is authorized. An organization flag is needed by both the web
and OAuth publisher. An explicitly attached, confirmed channel manager opens
Channel details, selects an attached OAuth application, and starts pairing.
The challenge expires after ten minutes and can be used once. Pending setup
polls for completion; an existing Board remains visible during replacement.

Load the connector token into `CAMPSITE_BEADS_OAUTH_TOKEN` through the
operator's secret-management workflow. Keep it out of command arguments and
logs. Pass the single-use challenge through stdin, for example from a shell
variable populated without echoing it:

```bash
printf '%s\n' "$CAMPSITE_BEADS_PAIRING_CHALLENGE" | script/publish-beads-board \
  --api-base-url "$CAMPSITE_API_URL" \
  --org "$CAMPSITE_ORG" \
  --project-id "$CAMPSITE_CHANNEL_ID" \
  --repository "$BEADS_REPOSITORY" \
  --beads-bin /opt/homebrew/bin/bd \
  --pair
```

After verification, Channel details shows the **Publisher source id** and
opaque Beads project id. An attached OAuth application can also read the safe
Board response from
`GET /v1/organizations/:org/projects/:project/beads_source/snapshot`.
Publish one snapshot with:

```bash
script/publish-beads-board \
  --api-base-url "$CAMPSITE_API_URL" \
  --org "$CAMPSITE_ORG" \
  --project-id "$CAMPSITE_CHANNEL_ID" \
  --source-id "$CAMPSITE_BEADS_SOURCE_ID" \
  --source-project-id "$BEADS_PROJECT_ID" \
  --repository "$BEADS_REPOSITORY" \
  --beads-bin /opt/homebrew/bin/bd
```

The publisher exits after one attempt. The operator owns the trigger and
publication frequency; no scheduler or synchronization SLA is supplied.
HTTP connection timeout is five seconds, and read/write timeouts are twenty
seconds. A failed request prints a bounded diagnostic and preserves the last
accepted Campsite snapshot. The repository path and bearer token are not
included in the payload.

## Access and lifecycle

Only explicit kept channel members can read the Board, source summary, and
roster. Public-channel visibility by itself grants no Board access. Attached
guests can read the safe projection but cannot manage the source. Source
management uses the API's `viewer_can_manage_beads_source` capability.

Organization admins can set **Agent-capable integration** in an integration's
General settings. A generic integration is not an agent by default. The roster
shows `Attached`, and combines `Agent` and `Beads publisher` only when both
roles apply. It does not report live availability.

Archive rejects new ingest and preserves existing snapshots. Unarchive allows
ingest again. Removing the connector's channel membership blocks publication
without deleting the last snapshot. Detaching the source removes its cached
snapshots and hides Board navigation; it never modifies Beads. Existing channel
exports exclude Board data and the roster.

## Rollout and rollback boundary

The additive migration is
`20260828130000_create_project_beads_board_foundation.rb`. It introduces three
tables and the default-false `agent_capable` column. Schema loading, rollback,
and reapplication have been exercised on a separate empty local database.

A future approved rollout needs the exact API and web revisions checked
independently, the migration applied before enabling the organization flag,
and the repository's homelab preflight. The publisher requires no worker
deployment. No deployment has been performed by this completion task.

The first rollback action is disabling the organization feature flag. This
blocks ingest and hides setup and navigation while retaining stored snapshots.
Dropping tables or deleting source data is a separate destructive cleanup
decision, not part of that rollback. Beads remains authoritative throughout.
