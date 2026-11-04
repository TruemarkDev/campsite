## Why

The `add-mcp-server` change shipped a remote MCP server with 16 read/write tools
over posts, comments, reactions, messages, notes, projects, organizations, and
members. That is enough to _demo_ an agent reading and writing Campsite content,
but **not enough to run a real multi-agent loop on top of Campsite** ("loop
engineering" — using Campsite as the async coordination substrate between an
orchestrator and worker agents).

A loop needs three primitives the current tool set is missing:

1. **Self-identity** — an agent must know _who it is_ (its user identity and its
   per-org member id) to recognize when it has been @mentioned or assigned, and
   to filter "mine".
2. **An inbox** — an agent must be able to poll _what is addressed to it_ and mark
   items handled. Today the only option is brute-forcing `list_posts` and diffing,
   which misses messages/mentions and does not scale.
3. **A durable working doc** — an agent needs a place to write a plan, status, and
   results that persists across turns. Notes are read-only over MCP today.

Every capability below already exists in the `/api/v1` REST API (notifications,
follow-ups, note create/update, current-user), so each new tool is a thin
`McpTool` wrapper over existing controllers/services and Pundit policies — the
same pattern `add-mcp-server` established. No new domain logic, no inference.

## What Changes

Add new MCP tools, grouped by how much they unblock an agent loop. All run through
the same Pundit authorization and Blueprinter serialization as the REST API.

- **Tier 1 (minimum viable loop) — this change implements these:**
  - `whoami` — returns the connected user's identity plus, per organization they
    belong to, their member public id (the `<@member_public_id>` used for mentions
    and DM recipients).
  - `list_notifications` — the agent's inbox: org-scoped, supports `unread` and a
    `filter` (home/activity), cursor-paginated. Wraps `NotificationsController#index`.
  - `mark_notification_read` — mark a notification (and its same-target siblings)
    read, so the loop does not reprocess handled items. Wraps
    `Notifications::ReadsController#create`.
  - `create_note` — create a note with `title` + `description_html` (+ optional
    project), as the durable per-run working doc. Wraps `NotesController#create`.
    Requires a new `write_note` OAuth scope.
  - `update_note` — update a note's `title` (matching the REST contract). Requires
    `write_note`.

- **Tier 2 (coordination) — specified here, deferred to a follow-up change:**
  - `create_follow_up` on a post/comment/note/thread — Campsite-native
    assign/remind, the cleanest hand-off + work-queue primitive.
  - `resolve_post` / post status, `update_post` / edit own comment, reply-to-comment.
  - `create_project` to spin up an isolated workspace per run.

- **Tier 3 (richer artifacts & protocol) — specified here, deferred:**
  - attachment/file upload for agent-produced artifacts; MCP **resources**
    (addressable `resource://` URIs + change subscriptions) and **prompts**
    (reusable templates).

- Add a **`write_note`** OAuth scope to the Doorkeeper `optional_scopes` list and
  to the MCP consent labels, gating the note-write tools.

## Capabilities

### Modified Capabilities

- `mcp-tools`: adds the agent-loop tool set (self-identity, notifications inbox,
  note creation/update) to the existing catalog, and a `write_note` scope gating
  note writes. Read-of-self and inbox tools gate on the `mcp` scope only;
  note-write tools additionally require `write_note`.

## Impact

- **New code**: five new `McpTool` subclasses (`whoami`, `list_notifications`,
  `mark_notification_read`, `create_note`, `update_note`) registered in
  `McpToolRegistry`; one new `write_note` scope entry in the Doorkeeper
  initializer; tests in `test/controllers/mcp_controller_test.rb`.
- **Reused, unchanged contracts**: `NotificationsController`,
  `Notifications::ReadsController`, `NotesController`, `UsersController#me`, their
  Pundit policies, and the `NotificationPageSerializer`/`NoteSerializer`/
  `CurrentUserSerializer`. No policy is bypassed.
- **Known limitation (documented, deferred)**: a note's **body** can only be set
  at creation via `description_html`. Editing an existing note's body goes through
  `notes/sync_states` and requires a valid collaborative `description_state`
  (Yjs/ProseMirror), so `update_note` here covers `title` only and an
  `append_to_note`/body-edit tool is explicitly out of scope until that state can
  be generated safely. Agents should create a fresh note per run rather than
  append to a shared one.
- **Out of scope**: Tier 2 and Tier 3 tools (specified above for prioritization,
  implemented in follow-up changes), any LLM/inference, and any hard-delete/bulk
  tool.
