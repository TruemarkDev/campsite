## Why

`add-mcp-agent-loop-tools` (Tier 1) gave a connected agent the minimum loop:
identity (`whoami`), an inbox (`list_notifications` / `mark_notification_read`),
and a durable working doc (`create_note` / `update_note`). An agent can now poll
what is addressed to it and record results.

Tier 2 is **coordination**: the actions a team of people and agents take *on the
work itself* once it's in flight — iterate on a post, close it out, thread a reply
onto a discussion, spin up a workspace for a run, and queue a personal follow-up.
Without these, an agent can talk but cannot drive a piece of work to "done":

- it cannot mark a post **resolved** (the real "done" signal — the `status` enum
  is only `none`/`feedback_requested`, so resolution, not status, is closure),
- it cannot **edit its own post** to incorporate feedback,
- it cannot **reply to a specific comment** (only add a flat top-level comment),
- it cannot **create a project** to isolate a run, and
- it cannot **queue a follow-up** reminder on something it must return to.

As in Tier 1, every action already exists in `/api/v1` and is guarded by Pundit,
so each tool is a thin `McpTool` wrapper — no new domain logic, no inference.

Note on hand-off: assigning work to *another* member is already possible today via
`@mention` (in `create_post`/`add_comment`), which lands a notification in that
member's inbox that they poll with `list_notifications`. A **follow-up** in
Campsite is a *personal reminder* on a subject, not an assignment to someone else —
this change exposes it as such (self-scoped), not as a hand-off primitive.

## What Changes

Add five MCP tools, each running through the same Pundit authorization and
Blueprinter serialization as the REST API.

- `resolve_post` (requires `write_post`) — resolve a post (optionally with a
  resolution HTML note or by pointing at an existing `comment_id`), or unresolve it
  via a `resolved: false` flag. Wraps `Posts::ResolutionsController` (`post.resolve!`
  / `post.unresolve!`), authorizing `:resolve?`.
- `update_post` (requires `write_post`) — edit a post's `title`,
  `description_html`, and/or move it to another `project_id`. Wraps
  `PostsController#update` (`post.update_post`), authorizing `:update?`.
- `reply_to_comment` (requires `write_post`) — reply to an existing comment,
  creating a threaded child via `Comment.create_comment(parent:)`. Authorizes the
  parent's subject `:create_comment?`. Complements the existing flat `add_comment`.
- `create_project` (requires `write_project`) — create a project/workspace with a
  `name`, optional `description`, and `private` flag. Wraps `ProjectsController#create`,
  authorizing `:create_project?`.
- `create_follow_up` (requires `mcp` only) — set a **personal** follow-up reminder
  on a post, note, or comment at a `show_at` time. Self-scoped (creates a follow-up
  for the connecting member only) and discards superseded home-inbox notifications,
  mirroring the REST follow-up controllers. Documented as a deliberate self-only,
  no-write-scope exemption, consistent with `mark_notification_read`.

## Capabilities

### Modified Capabilities
- `mcp-tools`: adds the coordination tool set (resolve/edit posts, threaded comment
  replies, project creation, personal follow-ups) to the existing catalog. The four
  content-mutating tools require their matching `write_post`/`write_project` scope;
  `create_follow_up` is self-scoped and gates on the `mcp` scope only.

## Impact

- **New code**: five new `McpTool` subclasses (`resolve_post`, `update_post`,
  `reply_to_comment`, `create_project`, `create_follow_up`) registered in
  `McpToolRegistry`; tests in `test/controllers/mcp_controller_test.rb`. No new
  OAuth scope is needed (`write_post`, `write_project`, `mcp` already exist).
- **Reused, unchanged contracts**: `Posts::ResolutionsController`,
  `PostsController#update`, `Comment.create_comment`, `ProjectsController#create`,
  the polymorphic follow-up controllers, their Pundit policies (`:resolve?`,
  `:update?`, `:create_comment?`, `:create_project?`, `:create_follow_up?`), and the
  `PostSerializer`/`CommentSerializer`/`ProjectSerializer`/`FollowUpSerializer`. No
  policy is bypassed.
- **Deliberately excluded**: `set_post_status` (the `status` enum carries no
  "done"/"blocked" state — resolution is closure); editing another member's content;
  assigning a follow-up to someone else (not a Campsite concept — use `@mention`);
  and any hard-delete/bulk tool.
- **Out of scope**: Tier 3 (attachments/upload, MCP resources + subscriptions,
  prompts) and any LLM/inference.
