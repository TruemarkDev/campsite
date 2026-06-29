## ADDED Requirements

### Requirement: Tools wrap existing domain logic under Pundit authorization

Every MCP tool SHALL execute against the same models, services, and Pundit
policies used by the `/api/v1` REST API. A tool SHALL NOT bypass authorization:
if the acting user is not permitted to perform an action via the REST API, the
equivalent tool call SHALL also be denied.

#### Scenario: Tool reuses existing authorization

- **WHEN** a user calls a tool for a resource they cannot access under the REST API's Pundit policy
- **THEN** the tool returns an authorization error and performs no read or write

#### Scenario: Tool output mirrors API serialization

- **WHEN** a read tool returns a resource
- **THEN** the resource is shaped by the same serializer (or an equivalent subset) the REST API uses, scoped to the acting user

### Requirement: Tools are multi-org and scoped to the user's memberships

A single `mcp` connection SHALL act across all organizations the authenticated
user belongs to, matching the existing frontend integration. Tools that operate
within an organization SHALL accept an organization argument (slug/public id),
and the server SHALL verify the user has a kept membership in that organization
before performing any read or write. A `list_organizations` tool SHALL let the
client discover the organizations the user can act in.

#### Scenario: User acts across multiple organizations with one connection

- **WHEN** a user who belongs to several organizations calls an org-scoped tool with a given organization argument
- **THEN** the server operates within that organization using the user's membership there, without requiring a separate connection per organization

#### Scenario: Org the user does not belong to is rejected

- **WHEN** a user calls an org-scoped tool with an organization they have no kept membership in
- **THEN** the server returns an authorization error and performs no read or write

### Requirement: Read tools

The system SHALL provide read tools covering the core Campsite domain: listing
and searching posts, reading a post with its comments, listing projects, listing
message threads and reading recent messages, listing/reading notes, and listing
the organizations the user belongs to. Read tools SHALL be paginated or limited
to avoid unbounded responses.

#### Scenario: List recent posts in a project

- **WHEN** a user calls the list-posts tool with an organization and optional project filter
- **THEN** the server returns a bounded, paginated set of posts the user can see

#### Scenario: Search posts

- **WHEN** a user calls the search tool with a query string
- **THEN** the server returns matching posts the user is authorized to view

#### Scenario: Read a post with comments

- **WHEN** a user calls the read-post tool with a post identifier
- **THEN** the server returns the post and its comments if the user may view it, or an error if not

### Requirement: Write tools

The system SHALL provide write tools for the most useful authoring actions:
creating a post, adding a comment to a post or note, and adding a reaction.
Write tools SHALL require the appropriate `write_*` scope in addition to `mcp`,
SHALL validate input against the same model validations as the REST API, and
SHALL be safe to describe to a user before execution (clear names and
descriptions).

#### Scenario: Create a post

- **WHEN** a user with the write-post scope calls the create-post tool with a title/body and target project
- **THEN** the server creates the post under the user's identity and returns the created post

#### Scenario: Comment on a post

- **WHEN** a user calls the add-comment tool with a post identifier and body
- **THEN** the server creates the comment under the user's identity if authorized, or returns an error if not

#### Scenario: Write blocked without write scope

- **WHEN** a user whose token lacks the relevant `write_*` scope calls a write tool
- **THEN** the server denies the call and creates nothing

### Requirement: Destructive actions are excluded from the initial tool set

The initial tool catalog SHALL NOT include hard-delete or bulk-destructive
operations. Tools SHALL be limited to reads and additive writes (create post,
comment, react) to keep the connector safe by default.

#### Scenario: No delete tool is advertised

- **WHEN** a client lists tools
- **THEN** no tool that permanently deletes posts, comments, projects, or organizations is present
