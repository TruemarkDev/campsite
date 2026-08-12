## Purpose

Allow MCP clients to identify themselves through securely fetched Client ID
Metadata Documents while preserving Campsite's existing OAuth clients and
making authorization responses unambiguous about their issuer.

## ADDED Requirements

### Requirement: Authorization-server metadata advertises implemented registration mechanisms

The authorization server SHALL advertise
`client_id_metadata_document_supported: true` only when its authorization and
token endpoints accept CIMD clients end to end. It SHALL continue to advertise
the DCR `registration_endpoint` while DCR remains supported.

#### Scenario: Client discovers CIMD support

- **WHEN** an MCP client reads Campsite's RFC 8414 authorization-server metadata
- **THEN** the response identifies CIMD as supported and still includes the DCR registration endpoint

#### Scenario: Incomplete rollout is not advertised

- **WHEN** CIMD client resolution is unavailable or disabled
- **THEN** authorization-server metadata does not claim CIMD support

### Requirement: URL client IDs resolve through Client ID Metadata Documents

The authorization server SHALL treat an eligible absolute HTTPS URL with a path
component as a CIMD `client_id`, fetch the JSON metadata document at that exact
URL, and require non-empty `client_id`, `client_name`, and `redirect_uris`
properties. The document's `client_id` SHALL exactly equal the requested URL.
The same validated client identity SHALL be used throughout authorization-code
issuance and token redemption under the existing S256 PKCE and scope rules.

#### Scenario: Valid CIMD public client completes authorization

- **WHEN** a client supplies an eligible URL whose valid document identifies the same client and includes the requested redirect URI
- **THEN** the user can consent, receive an authorization code, and redeem it with that URL client ID under the existing PKCE flow

#### Scenario: Document client ID does not match its URL

- **WHEN** a fetched document's `client_id` differs from the URL used as the client ID
- **THEN** authorization fails as an invalid client and no authorization code or token is issued

#### Scenario: Metadata is unavailable or malformed

- **WHEN** the document cannot be fetched, is not a successful response, exceeds the response limit, is not a JSON object, or lacks a required property
- **THEN** authorization fails closed and no authorization code or token is issued

#### Scenario: Noneligible URL is not fetched

- **WHEN** a client ID uses a non-HTTPS scheme, lacks an authority or path component, contains userinfo or a fragment, or is otherwise not an eligible CIMD URL
- **THEN** it is rejected as an invalid client without fetching the URL

### Requirement: Metadata retrieval is resistant to SSRF and resource exhaustion

The authorization server MUST fetch CIMD metadata without credentials using
verified HTTPS, MUST reject non-public destinations, MUST apply the same checks
after DNS resolution and at every redirect, and MUST bound redirects, connection
and response time, response bytes, and JSON parsing. It MUST NOT fetch optional
URLs found inside the metadata document as part of client resolution.

#### Scenario: Client ID resolves to an internal destination

- **WHEN** the client-ID host or a redirect target resolves to a private, loopback, link-local, multicast, unspecified, reserved, or otherwise non-public address
- **THEN** the server makes no request to that destination and rejects the client

#### Scenario: Redirect attempts to escape fetch policy

- **WHEN** metadata retrieval redirects to HTTP, a URL with userinfo, a disallowed address, or beyond the redirect limit
- **THEN** retrieval stops and authorization fails without issuing a code or token

#### Scenario: Metadata refers to an optional asset

- **WHEN** an otherwise valid document includes `logo_uri`, `client_uri`, `jwks_uri`, or another optional URL
- **THEN** client resolution does not fetch that URL

### Requirement: Authorization redirect URIs exactly match validated metadata

The authorization server MUST require the authorization request's
`redirect_uri` to exactly equal an entry in the validated document's
`redirect_uris` array and MUST continue to apply Campsite's OAuth redirect URI
security policy. It MUST NOT redirect an authorization response to an
unvalidated URI.

#### Scenario: Redirect URI is registered exactly

- **WHEN** the requested redirect URI exactly equals a valid entry in the metadata document
- **THEN** redirect validation succeeds and the authorization flow may proceed

#### Scenario: Redirect URI differs from the document

- **WHEN** the requested redirect URI differs by scheme, host, port, path, query, case-sensitive content, or any other character from every registered entry
- **THEN** authorization is rejected and no response is redirected to that unvalidated URI

### Requirement: Consent identifies the fetched client and redirect destination

For a CIMD authorization request, the consent experience SHALL display the
validated `client_name`, the client-ID hostname, and the redirect-URI hostname
before the user approves access.

#### Scenario: User reviews a CIMD client

- **WHEN** a valid CIMD client reaches the consent step
- **THEN** the user can see the client name, client-ID host, redirect host, and requested scopes before approving

### Requirement: Valid metadata is cached without authorizing stale or invalid documents

The authorization server SHALL cache only successfully fetched and validated
metadata, SHALL respect HTTP freshness information within finite deployment
bounds, and SHALL completely refetch and revalidate an expired entry. Failed
fetches, error responses, and invalid documents MUST NOT be cached as valid
client metadata, and stale metadata MUST NOT be used after a refresh failure.

#### Scenario: Fresh validated metadata is reused

- **WHEN** a valid cached document remains fresh under its HTTP caching metadata and server bounds
- **THEN** a later authorization may reuse that validated document without another network request

#### Scenario: Cached metadata expires

- **WHEN** a cached document is no longer fresh
- **THEN** the next authorization refetches and fully revalidates it before proceeding

#### Scenario: Refresh fails after expiry

- **WHEN** an expired document cannot be fetched or no longer validates
- **THEN** authorization fails and the stale document is not used

### Requirement: Dynamic Client Registration remains backward compatible during deprecation

The authorization server SHALL keep the existing RFC 7591 registration endpoint,
registered client credentials, and abuse throttle operational for at least 12
months after MCP 2026-07-28. CIMD support SHALL NOT invalidate, migrate, or
silently reinterpret existing DCR or pre-registered clients.

#### Scenario: Existing DCR client connects during the compatibility window

- **WHEN** a previously registered client authorizes or redeems a code before 2027-07-28
- **THEN** its existing client ID and applicable credentials continue to work under the existing OAuth rules

#### Scenario: New client falls back to DCR

- **WHEN** an MCP client chooses the advertised registration endpoint during the compatibility window
- **THEN** it can register under the existing throttled DCR behavior and use the returned client credentials

### Requirement: Authorization responses identify their issuer

When RFC 9207 support is advertised, every successful or error authorization
response produced by the supported authorization-code flow SHALL include an
`iss` parameter exactly equal to the `issuer` in authorization-server metadata.
The metadata SHALL set
`authorization_response_iss_parameter_supported: true` only while this behavior
is enabled.

#### Scenario: Successful response contains issuer

- **WHEN** the authorization server redirects a successful authorization-code response
- **THEN** the response contains `iss` exactly matching the advertised issuer

#### Scenario: Error response contains issuer

- **WHEN** the authorization server returns an OAuth authorization error
- **THEN** the error response contains `iss` exactly matching the advertised issuer

#### Scenario: Issuer response support is not implemented

- **WHEN** the server cannot add `iss` consistently to both successful and error authorization responses
- **THEN** metadata does not advertise `authorization_response_iss_parameter_supported: true`
