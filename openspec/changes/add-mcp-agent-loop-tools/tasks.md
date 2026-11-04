## 1. Scope

- [x] 1.1 Add `write_note` to `optional_scopes` in `config/initializers/doorkeeper.rb`
- [x] 1.2 (N/A) No per-scope consent label map exists in the app — Doorkeeper renders scopes without per-scope copy; nothing to add
- [x] 1.3 Add `write_note` to `ALL_SCOPES` in `test/controllers/mcp_controller_test.rb`

## 2. Tier 1 read/identity tools

- [x] 2.1 `whoami` — returns `CurrentUserSerializer` payload + a `memberships`
      array of `{ org_slug, org_name, member_id }`; not org-scoped; `mcp` scope only
- [x] 2.2 `list_notifications` — org-scoped, `unread` boolean + `filter`
      (home/activity) + pagination; wraps `NotificationsController#index`;
      `NotificationPageSerializer`; `mcp` scope only
- [x] 2.3 `mark_notification_read` — org-scoped, by `notification_id`; wraps
      `Notifications::ReadsController#create`; self-only; `mcp` scope only

## 3. Tier 1 note-write tools

- [x] 3.1 `create_note` — org-scoped; `title` + `description_html` (+ optional
      `project_id`); `enrich_mentions`; `:create_note?`; `NoteSerializer`; requires
      `write_note`
- [x] 3.2 `update_note` — org-scoped; `note_id` + `title` (title only, per REST);
      `:update?`; requires `write_note`

## 4. Registration & docs

- [x] 4.1 Register the new tools in `McpToolRegistry` (reads vs writes)
- [x] 4.2 Update `docs/mcp_server.md` with the new tools, the `write_note` scope,
      and the "create a fresh note per run; body edits unsupported" guidance

## 5. Tests & gates

- [x] 5.1 `whoami` returns identity + per-org member ids
- [x] 5.2 `list_notifications` returns the user's inbox; `unread` filter works;
      cross-org request is denied
- [x] 5.3 `mark_notification_read` marks the notification read; not-found path
- [x] 5.4 `create_note` creates a note; blocked without `write_note`; Pundit-denial
- [x] 5.5 `update_note` updates the title; blocked without `write_note`
- [x] 5.6 Run `bundle exec rubocop` and `bin/rails test test/controllers/mcp_controller_test.rb`; fix failures

## 6. Deferred (specified in proposal, not implemented here)

- [ ] 6.1 Tier 2: `create_follow_up`, `resolve_post`/status, `update_post`/edit
      comment, reply-to-comment, `create_project`
- [ ] 6.2 Tier 3: attachment/file upload, MCP resources (+ subscriptions), MCP prompts
- [ ] 6.3 Note body edit / `append_to_note` once a valid `description_state` can be generated
