## Why

We want to let people use Campsite from inside an LLM client (Claude, etc.) the
same way they connect Notion or PostHog today — pick "Campsite" from the
connector list, sign in, and grant access. Those connectors are **remote MCP
servers** that the client talks to over HTTP and authorizes with OAuth. Campsite
already exposes its domain over a REST API (`/api/v1/...`) and already runs a
full Doorkeeper OAuth2 provider with scopes and an `OauthApplication` model, so
the missing piece is an MCP surface that reuses both. The MCP server itself does
**no LLM inference** — the connecting client supplies the model; our server only
exposes tools/resources and runs them against existing Campsite logic.

## What Changes

- Add a **remote MCP server mounted inside the Rails API** (not a separate
  service), served over Streamable HTTP at a stable path (e.g. `/mcp`). Mounting
  reuses Campsite's existing authentication, Pundit policies, serializers, and
  models directly instead of duplicating them behind a second network hop.
- Add an **MCP tool layer** mapping the most useful read **and write** actions to
  existing API/domain logic — e.g. list/search/read posts, comments, messages,
  notes, projects, and organizations; create posts, comment on posts/notes, and
  add reactions. Every tool runs through the same Pundit authorization as the REST
  API.
- Reuse the **existing Doorkeeper OAuth2** provider as the authorization server.
  Add the OAuth discovery + dynamic-client-registration endpoints that remote MCP
  clients require so "Add connector → Campsite → sign in" works without any
  hand-provisioned credentials (the same UX as the Notion/PostHog connectors).
- Add an **`mcp` OAuth scope** (plus reuse existing `read_*` / `write_*` scopes)
  so users grant a single, clearly-labeled permission to the connector, and the
  consent screen names Campsite.
- Add a new gem dependency for the MCP protocol/transport implementation.

## Capabilities

### New Capabilities
- `mcp-server`: A remote, OAuth-authorized MCP endpoint mounted in the Rails API
  that advertises the protocol handshake, lists available tools, and dispatches
  tool calls to Campsite domain logic under the authenticated user's permissions.
- `mcp-tools`: The catalog of read and write tools exposed over MCP (posts,
  comments, messages, notes, projects, organizations, reactions) and their
  input/output contracts and authorization behavior.
- `mcp-oauth-connect`: The OAuth authorization flow for remote MCP clients —
  protected-resource and authorization-server discovery metadata, dynamic client
  registration, the `mcp` scope, and consent — so a client like Claude can
  connect Campsite the same way it connects Notion or PostHog.

### Modified Capabilities
<!-- None: there is no existing OpenSpec spec for the Doorkeeper/OAuth or REST API
     behavior in openspec/specs/, so this is purely additive. -->

## Impact

- **New code**: a mountable MCP Rack/engine endpoint and routing entry; an MCP
  tool registry + per-tool classes that wrap existing controllers/services;
  OAuth discovery (`/.well-known/oauth-protected-resource`,
  `/.well-known/oauth-authorization-server`) and dynamic-client-registration
  endpoints; an `mcp` scope.
- **Reused, unchanged contracts**: Doorkeeper config, `OauthApplication`/
  `AccessToken`, Pundit policies (`app/policies/`), Blueprinter serializers
  (`app/serializers/`), and the existing `/api/v1` domain logic. Tools call the
  same authorization paths, so no policy is bypassed.
- **Dependencies**: one new gem for MCP (latest stable; verified at install time).
- **Config/infra**: a new public route on the API host (Hatchbox/nginx) plus the
  OAuth metadata endpoints; an entry in the OAuth scope list. No new datastore.
- **Out of scope**: a standalone MCP microservice, any LLM/inference calls from
  the server, and changes to the upstream Fly deploy tooling.
