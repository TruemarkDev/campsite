## ADDED Requirements

### Requirement: Remote MCP endpoint mounted in the Rails API

The system SHALL expose a remote MCP server over Streamable HTTP at a stable
path on the API host, mounted within the existing Rails application rather than
running as a separate service. The endpoint SHALL implement the MCP `initialize`
handshake and advertise its protocol version and the `tools` capability.

#### Scenario: Client completes the MCP handshake

- **WHEN** an authorized MCP client sends an `initialize` request to the MCP endpoint
- **THEN** the server responds with its supported protocol version, server name/version, and a capabilities object that includes `tools`

#### Scenario: Endpoint is reachable over HTTP on the API host

- **WHEN** a client requests the configured MCP path (e.g. `/mcp`) on the API host
- **THEN** the request is handled by the in-process MCP server, not proxied to a separate service

### Requirement: Every MCP request is authenticated and authorized as a Campsite user

The MCP endpoint SHALL require a valid Doorkeeper access token carrying the
`mcp` scope. Each request SHALL resolve to the token's resource-owner user and
organization context, and all downstream work SHALL run under that identity.

#### Scenario: Missing or invalid token is rejected

- **WHEN** a request reaches the MCP endpoint without a valid bearer access token
- **THEN** the server responds with HTTP 401 and a `WWW-Authenticate` header pointing at the protected-resource metadata

#### Scenario: Token without the mcp scope is rejected

- **WHEN** a request presents a valid access token that lacks the `mcp` scope
- **THEN** the server responds with an authorization error and does not execute any tool

#### Scenario: Authenticated request runs as the token's user

- **WHEN** a valid `mcp`-scoped token is presented
- **THEN** the server establishes the current user and organization membership from the token's resource owner before dispatching any tool

### Requirement: Tool discovery

The MCP endpoint SHALL respond to `tools/list` with the catalog of available
tools, each with a name, human-readable description, and JSON Schema for its
inputs.

#### Scenario: Listing tools

- **WHEN** an authorized client sends `tools/list`
- **THEN** the server returns every registered tool with its name, description, and input schema

### Requirement: Tool dispatch and error reporting

The MCP endpoint SHALL dispatch `tools/call` requests to the named tool, return
the tool's structured result on success, and return a tool-level error result
(not a transport crash) when a tool fails, is unknown, or receives invalid
input.

#### Scenario: Successful tool call

- **WHEN** an authorized client calls a registered tool with valid arguments
- **THEN** the server executes it under the user's permissions and returns the tool's result content

#### Scenario: Unknown or invalid tool call

- **WHEN** a client calls a tool that does not exist or supplies arguments that fail schema validation
- **THEN** the server returns an MCP error result describing the problem and does not affect other requests
