## ADDED Requirements

### Requirement: Post resolution and editing tools

The server SHALL expose a `resolve_post` tool and an `update_post` tool, both
organization-scoped and both requiring the `write_post` scope. `resolve_post` SHALL
resolve a post (optionally recording resolution HTML or referencing an existing
comment) or unresolve it, via the same `resolve!`/`unresolve!` path and `:resolve?`
authorization as the REST API. `update_post` SHALL edit a post's title and/or body
and optionally move it to another project, via the same `update_post` path and
`:update?` authorization. Neither tool SHALL bypass the post's Pundit policy.

#### Scenario: Agent resolves a post

- **WHEN** a user with the `write_post` scope calls `resolve_post` for a post they may resolve
- **THEN** the post is marked resolved and returned via the post serializer

#### Scenario: Agent unresolves a post

- **WHEN** a user calls `resolve_post` with `resolved: false`
- **THEN** the post is marked unresolved

#### Scenario: Agent edits its post

- **WHEN** a user with the `write_post` scope calls `update_post` with a new title or body for a post they may update
- **THEN** the post is updated and returned via the post serializer

#### Scenario: Post mutation blocked without scope or authorization

- **WHEN** a user lacking `write_post` calls `resolve_post`/`update_post`, OR a user calls them for a post their policy forbids
- **THEN** the tool returns a scope or authorization error and changes nothing

### Requirement: Threaded comment reply tool

The server SHALL expose a `reply_to_comment` tool, organization-scoped and requiring
the `write_post` scope, that creates a reply to an existing comment as a threaded
child via the same `Comment.create_comment` path the REST API uses, authorizing
against the parent comment's subject with `:create_comment?` and expanding
`<@member_public_id>` mentions.

#### Scenario: Agent replies to a comment

- **WHEN** a user with the `write_post` scope calls `reply_to_comment` with a parent comment id and body HTML
- **THEN** a reply is created as a child of that comment and returned via the comment serializer

#### Scenario: Reply blocked without scope

- **WHEN** a user lacking `write_post` calls `reply_to_comment`
- **THEN** the tool returns an error naming the required scope and creates nothing

### Requirement: Project creation tool

The server SHALL expose a `create_project` tool, organization-scoped and requiring
the `write_project` scope, that creates a project with a name and optional
description and privacy flag, via the same creation path and `:create_project?`
authorization as the REST API, with the connecting member as creator.

#### Scenario: Agent creates a project

- **WHEN** a user with the `write_project` scope calls `create_project` with a name
- **THEN** a project is created with that user as creator and returned via the project serializer

#### Scenario: Project creation blocked without scope or authorization

- **WHEN** a user lacking `write_project` calls `create_project`, OR a user whose policy forbids project creation calls it
- **THEN** the tool returns a scope or authorization error and creates nothing

### Requirement: Personal follow-up tool

The server SHALL expose a `create_follow_up` tool, organization-scoped, that sets a
personal follow-up reminder for the connecting member on a post, note, or comment at
a given time, via the same `follow_ups.create!` path and `:create_follow_up?`
authorization as the REST API. The follow-up SHALL be created only for the acting
member (never assigned to another member) and the tool SHALL require the `mcp` scope
only, as a deliberate self-only exemption documented in code.

#### Scenario: Agent queues a follow-up on a post

- **WHEN** a user calls `create_follow_up` with a post subject and a show_at time
- **THEN** a follow-up is created for that user on that post and returned via the follow-up serializer

#### Scenario: Follow-up is self-scoped across orgs

- **WHEN** a user calls `create_follow_up` for an organization they have no kept membership in
- **THEN** the tool returns an authorization error and creates nothing
