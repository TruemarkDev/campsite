## ADDED Requirements

### Requirement: Protected-resource metadata discovery

The system SHALL serve OAuth 2.0 Protected Resource Metadata (RFC 9728) at
`/.well-known/oauth-protected-resource` describing the MCP endpoint as a
protected resource and pointing to Campsite's authorization server. The MCP
endpoint's `401` responses SHALL include a `WWW-Authenticate` header that
references this metadata so a client can discover how to authorize.

#### Scenario: Client discovers the authorization server

- **WHEN** an MCP client fetches `/.well-known/oauth-protected-resource`
- **THEN** the response lists the resource identifier and the authorization-server URL(s) the client must use

#### Scenario: Unauthorized response advertises discovery

- **WHEN** the MCP endpoint returns 401 to an unauthenticated request
- **THEN** the `WWW-Authenticate` header includes a `resource_metadata` pointer to the protected-resource metadata

### Requirement: Authorization-server metadata discovery

The system SHALL serve OAuth 2.0 Authorization Server Metadata (RFC 8414) at
`/.well-known/oauth-authorization-server` advertising the existing Doorkeeper
authorization, token, and registration endpoints, the supported scopes
(including `mcp`), PKCE support, and supported grant types.

#### Scenario: Client reads authorization-server metadata

- **WHEN** an MCP client fetches `/.well-known/oauth-authorization-server`
- **THEN** the response advertises the authorization endpoint, token endpoint, registration endpoint, `code_challenge_methods_supported` including `S256`, and a `scopes_supported` list containing `mcp`

### Requirement: Dynamic client registration

The system SHALL accept OAuth 2.0 Dynamic Client Registration (RFC 7591) so a
remote MCP client can register itself and obtain client credentials without a
human pre-provisioning an `OauthApplication`. Registered clients SHALL be backed
by the existing `OauthApplication` model.

#### Scenario: Client registers itself

- **WHEN** an MCP client POSTs a registration request with its redirect URI(s) to the registration endpoint
- **THEN** the server creates an OAuth application and returns a `client_id` (and `client_secret` if confidential) usable for the authorization-code flow

### Requirement: Authorization-code flow with PKCE and consent

The connector SHALL authorize via the existing Doorkeeper authorization-code
flow with PKCE. The user SHALL be shown a consent screen that names Campsite and
the requested scopes (including `mcp`), and approval SHALL issue an access token
scoped to that user and organization.

#### Scenario: User connects Campsite from the client

- **WHEN** a user adds the Campsite connector and is redirected to Campsite's authorization endpoint with a PKCE challenge and the `mcp` scope
- **THEN** Campsite presents a consent screen, and on approval redirects back with an authorization code that the client exchanges for an `mcp`-scoped access token

#### Scenario: Connection works without manual credential provisioning

- **WHEN** a user follows the "Add connector → Campsite → sign in" flow end to end
- **THEN** no step requires an administrator to hand-create client credentials, mirroring the Notion/PostHog connector experience

### Requirement: The `mcp` scope

The system SHALL define an `mcp` OAuth scope used to gate access to the MCP
endpoint, alongside the existing `read_*` / `write_*` scopes that gate
individual read and write tools.

#### Scenario: mcp scope appears in supported scopes

- **WHEN** a client reads the authorization-server metadata or initiates authorization
- **THEN** `mcp` is an available, selectable scope
