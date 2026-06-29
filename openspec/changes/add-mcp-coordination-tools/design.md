## Context

Tools follow the `McpTool` pattern established in `add-mcp-server` and extended in
`add-mcp-agent-loop-tools`: `tool_name`, `description`, `org_scoped_schema`,
`#execute` calling `organization_context!` → `require_scope!` (writes) →
`authorize!` → serialize → `data_response`. Tests live in
`test/controllers/mcp_controller_test.rb`. This change adds five coordination tools
over existing controllers.

## Decisions

### Decision 1 — `resolve_post` covers closure; no `set_post_status`
`Post`'s `status` enum is only `{ none, feedback_requested }` (post.rb:196) — there
is no "done"/"blocked" state to set, so a status tool would be near-useless.
Closure is **resolution**: `Posts::ResolutionsController#create` calls
`post.resolve!(actor:, html:, comment_id:)` and `#destroy` calls
`post.unresolve!(actor:)`. The tool exposes one `resolve_post` with a `resolved`
boolean (default `true`): `true` → `resolve!` (passing optional `resolve_html` and
`comment_id`, both nullable like REST), `false` → `unresolve!`. Authorizes
`:resolve?`, requires `write_post`, returns `PostSerializer`.

### Decision 2 — `update_post` delegates to `post.update_post`
Mirrors `PostsController#update`: resolve an optional `project_id` via
`policy_scope(organization.projects).find_by!`, then
`post.update_post(actor: member, organization:, project:, params:)` with permitted
`title`/`description_html`. `enrich_mentions` is applied to `description_html`.
Authorizes `:update?`, requires `write_post`. The post's own validations/erroring
path returns a tool error on failure.

### Decision 3 — `reply_to_comment` is a distinct tool, not a flag on `add_comment`
A reply is `Comment.create_comment(params:, member:, parent: <comment>)` — the
`parent:` keyword threads it (`create_comment.rb:34` builds `parent.kept_replies`).
Keeping it a separate tool (rather than an optional `parent_comment_id` on
`add_comment`) keeps each tool's contract single-purpose and matches the registry
style. The parent comment is looked up within the org; authorization runs against
the parent's **subject** (`parent.subject`, a post/note) with `:create_comment?`,
exactly as the REST comment create does. Requires `write_post`, returns
`CommentSerializer`.

### Decision 4 — `create_project` exposes the safe subset
`ProjectsController#create` accepts many params (slack channel, members,
chat_format, onboarding). The tool exposes only `name` (required), `description`,
and `private`, building `organization.projects.build(creator: member, name:,
description:)`, setting `private` when requested, and saving inside the same
transaction shape (without the Slack/onboarding side-paths). Authorizes
`:create_project?`, requires `write_project`, returns `ProjectSerializer`.

### Decision 5 — `create_follow_up` is self-only, `mcp`-scope-only, documented
A Campsite follow-up is a **personal reminder** the member sets on a subject — it is
created via `<subject>.follow_ups.create!(organization_membership: member, show_at:)`
and is never an assignment to another member. The tool is polymorphic over post /
note / comment (resolved within the org), authorizes `:create_follow_up?`, and
calls `Notification.discard_home_inbox_notifications(member:, follow_up_subject:)`
like the REST controllers. Like `mark_notification_read`, it mutates only the
acting member's own state, so it is **deliberately gated by `mcp` alone** (no
`write_*` scope) and that exemption is stated explicitly in the class comment and
registry. `show_at` is an ISO8601 timestamp string.

### Decision 6 — hand-off uses `@mention`, not follow-ups
Assigning work to another agent/member is already expressible: `create_post` /
`add_comment` with `<@member_public_id>` lands a notification in that member's
inbox, which they poll via `list_notifications`. No new "assign" tool is needed,
and follow-ups are intentionally NOT overloaded to mean assignment.

## Risks / Trade-offs

- **`update_post` blast radius** — only the post's own `:update?` policy gates it;
  this is identical to the REST contract, so no new exposure. A member can only
  edit posts the policy already lets them edit.
- **`create_project` omits members/Slack** — intentional minimal surface; a project
  is created with the creator as owner and can be populated by other tools/UI later.
- **`create_follow_up` self-only exemption** — same reasoning as
  `mark_notification_read`; a read/`mcp`-only connector can manage its own reminders
  without a content-write grant.

## Migration / Rollout

No data migration, no new scope (reuses `write_post`, `write_project`, `mcp`).
Additive tools only; existing connectors are unaffected until they call the new
tools (and must already hold the relevant write scope for the content-mutating ones).
