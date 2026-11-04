## ADDED Requirements

### Requirement: Self-identity tool

The server SHALL expose a `whoami` tool that returns the connected user's identity
and, for each organization the user has a kept membership in, the user's member
public id (the id used for `<@member_public_id>` mentions and as a DM recipient).
The tool SHALL require only the `mcp` scope and SHALL NOT take an organization
argument.

#### Scenario: Agent discovers its identity and per-org member ids

- **WHEN** a connected user calls `whoami`
- **THEN** the result includes the user's identity (id, username, display name) and a list of `{ org_slug, member_id }` entries for every organization the user belongs to

### Requirement: Notifications inbox tools

The server SHALL expose a `list_notifications` tool and a `mark_notification_read`
tool, both organization-scoped. `list_notifications` SHALL return only the
authenticated user's notifications in the requested organization, support an
`unread` filter and cursor pagination, and serialize with the same serializer the
REST notifications endpoint uses. `mark_notification_read` SHALL mark a
notification owned by the user (and its same-target siblings) read. Both tools
SHALL require only the `mcp` scope, and SHALL operate solely on the acting user's
own inbox with no cross-user or cross-org effect.

#### Scenario: Agent polls its inbox

- **WHEN** a user calls `list_notifications` for an organization they belong to
- **THEN** the tool returns that user's notifications in that organization, honoring the `unread` filter and pagination

#### Scenario: Cross-org inbox access is rejected

- **WHEN** a user calls `list_notifications` for an organization they have no kept membership in
- **THEN** the tool returns an authorization error and reads no notifications

#### Scenario: Agent marks a handled notification read

- **WHEN** a user calls `mark_notification_read` with a notification id they own
- **THEN** that notification and its same-member-and-target siblings are marked read

#### Scenario: Marking a non-existent notification

- **WHEN** a user calls `mark_notification_read` with an id that is not their own or does not exist
- **THEN** the tool returns a not-found error and changes no state

### Requirement: Note creation and title-update tools

The server SHALL expose a `create_note` tool and an `update_note` tool, both
organization-scoped and both requiring the `write_note` scope. `create_note` SHALL
create a note owned by the acting member with a `title` and `description_html`
body (optionally within a project), expanding `<@member_public_id>` mentions, and
authorize via the same Pundit policy as the REST create. `update_note` SHALL
update a note's `title` only, matching the REST contract. Neither tool SHALL edit
an existing note's collaborative body.

#### Scenario: Agent creates a working-doc note

- **WHEN** a user with the `write_note` scope calls `create_note` with a title and HTML body
- **THEN** a note is created under the user's membership and returned via the note serializer

#### Scenario: Note write blocked without the write_note scope

- **WHEN** a user whose connection lacks the `write_note` scope calls `create_note` or `update_note`
- **THEN** the tool returns an error naming the required `write_note` scope and writes nothing

#### Scenario: Note write respects Pundit authorization

- **WHEN** a user calls `create_note` or `update_note` for a resource their Pundit policy forbids
- **THEN** the tool returns an authorization error and writes nothing

### Requirement: Note body editing is not exposed

The server MUST NOT expose any tool that edits an existing note's body until a
valid collaborative state can be generated; note bodies SHALL be settable only at
creation time via `create_note`. A note's body is collaborative state
(`description_state`) that must stay consistent across connected editors, so the
loop pattern is to create a new note per run rather than append to a shared one.

#### Scenario: No body-edit tool is advertised

- **WHEN** a client lists available tools
- **THEN** no tool that mutates an existing note's `description_html`/`description_state` is present (only `create_note` sets a body, at creation)
