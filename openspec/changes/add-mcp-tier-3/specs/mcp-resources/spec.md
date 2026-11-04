## ADDED Requirements

### Requirement: Server advertises the resources capability

The MCP server SHALL advertise the `resources` capability (with `listChanged`) in the
`initialize` handshake and SHALL serve `resources/list`, `resources/templates/list`,
and `resources/read`, exposing Campsite entities as addressable `campsite://` URIs.

#### Scenario: Client discovers resources support

- **WHEN** a client completes the `initialize` handshake
- **THEN** the server's advertised capabilities include `resources`

### Requirement: Campsite entities are addressable and readable as resources

The server SHALL expose URI templates of the form
`campsite://{org_slug}/{type}/{public_id}` for posts, notes, and message threads via
`resources/templates/list`, and SHALL resolve a `resources/read` for such a URI to the
entity's content rendered with the same serializer and authorized by the same Pundit
policy and read scope as the equivalent read tool. `resources/list` SHALL return a
bounded set of the connecting user's recent entities and SHALL NOT page the entire
workspace. An unknown URI SHALL return a not-found error and a forbidden entity SHALL
return an authorization error; no resource read SHALL bypass authorization or leak
across organizations.

#### Scenario: Client reads a post resource

- **WHEN** a client reads `campsite://{org_slug}/posts/{public_id}` for a post the
  user may view
- **THEN** the post is returned via the post serializer

#### Scenario: Resource read is authorized and org-isolated

- **WHEN** a client reads a `campsite://` URI for an entity the user's policy forbids,
  or in an organization the user has no kept membership in
- **THEN** the server returns an authorization error and discloses nothing

#### Scenario: Unknown resource URI

- **WHEN** a client reads a `campsite://` URI that resolves to no entity
- **THEN** the server returns a not-found error

### Requirement: Resource change subscriptions are conditional on transport support

The server SHALL advertise `resources.subscribe` and serve `resources/subscribe` /
`resources/unsubscribe` (emitting `notifications/resources/updated`) only when the
remote Streamable-HTTP transport is confirmed to hold a server→client stream
end-to-end in the deployment environment. When that support is not confirmed, the
server SHALL NOT advertise `resources.subscribe` and SHALL serve resources without
subscriptions.

#### Scenario: Subscriptions advertised only when supported

- **WHEN** the transport cannot hold a server→client stream in the deployment
- **THEN** the server does not advertise `resources.subscribe` and resource
  list/templates/read still function

#### Scenario: Subscribed client is notified of a change

- **WHEN** subscriptions are supported and a client subscribes to a resource URI and
  the underlying entity changes
- **THEN** the server emits a `notifications/resources/updated` for that URI
