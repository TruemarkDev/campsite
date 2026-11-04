## 1. Coordination tools

- [x] 1.1 `resolve_post` — org-scoped; `post_id`, `resolved` (bool, default true),
      optional `resolve_html` / `comment_id`; `resolve!`/`unresolve!`; `:resolve?`;
      requires `write_post`; `PostSerializer`
- [x] 1.2 `update_post` — org-scoped; `post_id` + optional `title`/`description_html`/
      `project_id`; `post.update_post`; `enrich_mentions`; `:update?`; requires
      `write_post`; `PostSerializer`
- [x] 1.3 `reply_to_comment` — org-scoped; `comment_id` + `body_html`;
      `Comment.create_comment(parent:)`; authorize parent.subject `:create_comment?`;
      `enrich_mentions`; requires `write_post`; `CommentSerializer`
- [x] 1.4 `create_project` — org-scoped; `name` (required) + optional `description`/
      `private`; `:create_project?`; requires `write_project`; `ProjectSerializer`
- [x] 1.5 `create_follow_up` — org-scoped; `subject_type` (post/note/comment) +
      `subject_id` + `show_at`; `<subject>.follow_ups.create!`; discard superseded
      home-inbox notifications; `:create_follow_up?`; self-only; `mcp` scope only;
      `FollowUpSerializer`

## 2. Registration & docs

- [x] 2.1 Register the new tools in `McpToolRegistry` (writes; `create_follow_up`
      grouped with reads w/ the documented self-only exemption comment)
- [x] 2.2 Update `docs/mcp_server.md` with the five tools and their scopes

## 3. Tests & gates

- [x] 3.1 `resolve_post` resolves and unresolves; blocked without `write_post`; Pundit-denial
- [x] 3.2 `update_post` edits title/description; blocked without `write_post`
- [x] 3.3 `reply_to_comment` creates a threaded reply; blocked without `write_post`
- [x] 3.4 `create_project` creates a project; blocked without `write_project`; Pundit-denial
- [x] 3.5 `create_follow_up` creates a follow-up on a post; self-only; cross-org denied
- [x] 3.6 Run `bundle exec rubocop` and `bin/rails test test/controllers/mcp_controller_test.rb`; fix failures

## 4. Deferred (Tier 3, separate change)

- [ ] 4.1 Attachment/file upload for agent-produced artifacts
- [ ] 4.2 MCP resources (addressable URIs + change subscriptions) and MCP prompts
