## Context

`add-mcp-server` established the `McpTool` base class (`app/mcp/mcp_tool.rb`): each
tool declares `tool_name`, `description`, and an `org_scoped_schema`, then
implements `#execute`, calling `organization_context!` to resolve the user's kept
membership and set `Current`, `require_scope!` for writes, `authorize!` for
Pundit, `paginate` for cursor pagination, and `serialize`/`data_response` to shape
output with the REST API's Blueprinter serializers. Tools are listed in
`McpToolRegistry` (`READ_TOOLS` / `WRITE_TOOLS`). Tests live in one integration
file, `test/controllers/mcp_controller_test.rb`, driven by `call_tool` /
`tool_error?` / `tool_text` / `structured_content` helpers.

This change adds the tools an agent needs to participate in a loop, reusing that
machinery verbatim.

## Goals / Non-Goals

**Goals:** self-identity, an inbox (read + mark-read), and durable-doc creation
over MCP, each a thin wrapper over an existing controller and policy.

**Non-Goals:** editing a note's collaborative body; Tier 2/3 tools; any new domain
logic, migration, or inference.

## Decisions

### Decision 1 — `whoami` returns identity + per-org member ids
`UsersController#me` serializes the user with `CurrentUserSerializer` (id,
username, display_name, …) but the user-level identity is not enough for a loop:
mentions and DM recipients use the **org member** public id, which differs per
org. So `whoami` returns the `CurrentUserSerializer` payload plus a `memberships`
array of `{ org_slug, org_name, member_id }` built from the user's kept
memberships. It is **not** org-scoped (no `org_slug` argument) because its job is
to tell the agent which orgs exist and what its id is in each. Gated by the `mcp`
scope only (pure read of self).
- *Alternative considered:* an org-scoped `whoami(org_slug)` returning one
  `OrganizationMember`. Rejected: the agent would have to already know its orgs,
  which is the thing `whoami` is supposed to reveal.

### Decision 2 — `list_notifications` is the inbox, org-scoped
Wraps `NotificationsController#index`, reading
`current_organization_membership.inbox_notifications` (or `.activity` for the
`activity` filter), with an `unread` boolean and cursor pagination via the shared
`PAGINATION_PROPERTIES`. Serialized with `NotificationPageSerializer`. Gated by
the `mcp` scope only (read). Because notifications are read from
`current_organization_membership`, a user only ever sees their own inbox in orgs
they belong to — the `organization_context!` membership check already guarantees
no cross-org leakage.

### Decision 3 — `mark_notification_read` is self-only, gated by `mcp` only
Wraps `Notifications::ReadsController#create`: looks the notification up via
`current_organization_membership.notifications.find_by!(public_id:)` and marks the
same-member-and-target siblings read. It mutates only the acting user's own inbox
state, carries no cross-user effect, and the REST API does not put it behind an
OAuth write scope, so this tool requires the `mcp` scope only (no `write_*`).
- *Alternative considered:* gating behind a write scope. Rejected: inconsistent
  with the self-only, low-risk nature and with the REST contract; it would force
  every loop connector to request a write scope just to keep its inbox tidy.

### Decision 4 — `create_note` requires a new `write_note` scope
Note creation is a genuine write, and the established convention is that write
tools call `require_scope!("write_<thing>")`. No `write_note` scope exists yet, so
add `write_note` to `optional_scopes` in `config/initializers/doorkeeper.rb` and
to the MCP consent scope labels. `create_note` wraps `NotesController#create`:
`current_organization_membership.notes.create!(title:, description_html:,
project:, project_permission:)`, enriching `<@member_public_id>` mentions in the
body via `enrich_mentions`, authorizing with `:create_note?`, serializing with
`NoteSerializer`.

### Decision 5 — `update_note` covers `title` only; body editing is deferred
The REST `NotesController#update` accepts only `title`. A note's body is
collaborative: it is written through `Notes::SyncStatesController#update`, which
requires `description_html` **and** a matching `description_state` (the Yjs/
ProseMirror binary CRDT state) and a `description_schema_version`. Setting
`description_html` without a consistent `description_state` would desync every
connected editor. Generating a valid `description_state` server-side from HTML is
real work and out of scope here. Therefore `update_note` mirrors the REST
contract (title only), and any body-edit/append tool is deferred until we can
produce a valid collaborative state. The loop pattern is "create a fresh note per
run", not "append to a shared note".

### Decision 6 — Tier 2/3 are specified in the proposal but not built here
To keep this change small and verifiable, only Tier 1 is implemented. Tier 2
(follow-ups, post resolve/edit, project create) and Tier 3 (attachments, MCP
resources/prompts) are captured in the proposal for prioritization and will land
as separate changes, each following the same wrapper pattern.

## Risks / Trade-offs

- **`description_state` desync** — mitigated by not exposing body edits at all
  (Decision 5).
- **Inbox volume** — `list_notifications` is cursor-paginated and bounded by the
  shared 1–100 limit, so a noisy inbox cannot return an unbounded payload.
- **Scope creep on consent** — only `write_note` is added; reads stay under the
  single `mcp` scope, so a read-only loop connector needs no new grant.

## Migration / Rollout

No data migration. The new `write_note` scope is additive to `optional_scopes`.
Existing connectors are unaffected; a connector must re-consent to obtain
`write_note` before the note-write tools succeed (they return a clear
"requires the 'write_note' scope" error otherwise).
