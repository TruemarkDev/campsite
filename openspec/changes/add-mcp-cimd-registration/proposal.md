## Why

MCP 2026-07-28 deprecates OAuth Dynamic Client Registration (RFC 7591) in
favor of Client ID Metadata Documents (CIMD), while Campsite currently
advertises and accepts only DCR for self-service MCP clients. Campsite needs to
accept the HTTPS-URL client identifiers preferred by new MCP clients without
breaking already-registered clients during the specification's deprecation
window.

## What Changes

- Accept a CIMD `client_id` in the existing Doorkeeper authorization-code +
  PKCE flow. When the client identifier is an eligible HTTPS URL, fetch its
  metadata document, validate the document and exact client-ID match, and
  require the authorization request's redirect URI to exactly match one of the
  document's registered redirect URIs.
- Make metadata retrieval safe for an unauthenticated, attacker-controlled URL:
  enforce HTTPS and a non-root path, block private/loopback/link-local and
  other non-public destinations across DNS resolution, reject HTTP redirects,
  bound time/response size, accept valid JSON only, and cache only valid
  documents while respecting HTTP cache headers.
- Advertise CIMD support with
  `client_id_metadata_document_supported: true` in RFC 8414 authorization-server
  metadata.
- Keep `POST /oauth/register` and its Rack::Attack throttle working for existing
  clients for no less than 12 months from the 2026-07-28 deprecation (no removal
  before 2027-07-28). Removing DCR later requires a separate reviewed change.
- Add RFC 9207's `iss` parameter to successful and error authorization
  responses and advertise
  `authorization_response_iss_parameter_supported: true`, after verifying the
  correct integration point for Campsite's pinned Doorkeeper version.
- Add request, validation, cache, SSRF, redirect-URI, discovery, DCR-compatibility,
  and RFC 9207 coverage, and update the MCP operator/client documentation.

## Capabilities

### New Capabilities

- `mcp-cimd-registration`: URL-based MCP client registration, metadata
  discovery and validation, safe caching, DCR compatibility, and authorization
  response issuer identification for Campsite's OAuth server.

### Modified Capabilities

<!-- None. `mcp-oauth-connect` is introduced by the still-open
     `add-mcp-server` change and is not yet a main spec under openspec/specs/.
     This change therefore defines the additive CIMD contract as its own
     capability instead of pretending to modify an archived capability. -->

## Impact

- **Authorization flow**: Doorkeeper client lookup at both authorization and
  token exchange must recognize validated URL client IDs, in addition to
  persisted `OauthApplication` UIDs. Campsite remains an authorization-code +
  PKCE provider with the existing `mcp` and `read_*` / `write_*` scopes.
- **Discovery**: `WellKnownController#oauth_authorization_server` gains the CIMD
  and RFC 9207 support indicators; the existing RFC 9728 protected-resource
  metadata remains unchanged.
- **New security boundary**: the authorization server fetches an untrusted URL,
  requiring a centralized outbound-fetch policy, bounded parsing, redirect
  rejection, and non-error caching.
- **Compatibility**: `Oauth::RegistrationsController`, `POST /oauth/register`,
  and its Rack::Attack throttle continue to serve DCR clients throughout the
  minimum compatibility window.
- **Likely affected code**: the custom Doorkeeper authorization controller,
  Doorkeeper application/client resolution used by authorization and token
  exchange, a CIMD fetch/validation/cache service, well-known metadata, OAuth
  tests, and `api/docs/mcp_server.md`.
- **Out of scope**: removing DCR; changing OAuth scopes or the MCP endpoint;
  implementing private-key JWT client authentication; fetching optional display
  assets such as `logo_uri`; or choosing a domain allowlist before deployment
  policy is decided.
