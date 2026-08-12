## Context

See `proposal.md` for the motivation. Campsite's authorization server is Rails
with Doorkeeper 5.6.9 (pinned in `api/Gemfile.lock`). Its current MCP connect
path is entirely persisted-client based:

- `Oauth::RegistrationsController#create` implements RFC 7591 at
  `POST /oauth/register`, creates an `OauthApplication`, and treats clients that
  declare `token_endpoint_auth_method: none` as public clients.
- `Doorkeeper::CustomAuthorizationsController` rejects a `client_id` unless a
  kept `OauthApplication` exists with that UID. Doorkeeper's authorization and
  token flows also resolve clients through its application model, and access
  grants/tokens reference an application row.
- `WellKnownController#oauth_authorization_server` advertises RFC 8414 metadata,
  the DCR endpoint, S256 PKCE, authorization-code/refresh-token grants, and the
  supported scopes. `mcp` is an optional Doorkeeper scope.
- Rack::Attack limits `POST /oauth/register` to five requests per IP per minute.

MCP 2026-07-28 says a CIMD client ID is an HTTPS URL with a path component. The
authorization server fetches JSON from that URL, verifies the document's
`client_id` exactly equals the URL, and verifies the request's `redirect_uri`
exactly matches a document entry. Valid metadata may be cached in accordance
with HTTP caching semantics. Fetch failure aborts authorization.

This adds an outbound request from an unauthenticated OAuth entry point. The
CIMD draft recommends a 5 KiB maximum response and calls out SSRF, DNS/private
addresses, metadata-cache correctness, redirect trust, and display identity as
security concerns. Optional URLs inside the document are data, not permission
to fetch more resources.

The lockfile establishes Doorkeeper 5.6.9 but does not establish RFC 9207
support. A scan of the locally installed 5.6.9 source found no `iss` response
parameter or `authorization_response_iss_parameter_supported` setting; its
`OAuth::CodeResponse#body` currently returns code/state only for this flow. The
implementation must still prove the supported extension point before choosing
a local override or dependency upgrade.

## Goals / Non-Goals

**Goals:**

- Add CIMD clients to the same authorization-code + S256 PKCE, consent, scope,
  grant, and token lifecycle used by persisted public clients.
- Centralize remote metadata retrieval, validation, caching, and observability
  so Doorkeeper entry points cannot apply different security rules.
- Preserve DCR and manually provisioned clients while CIMD adoption grows.
- Add RFC 9207 issuer identification without advertising it before both success
  and error responses comply.

**Non-Goals:**

- Implement `private_key_jwt` or fetch `jwks_uri`, `logo_uri`, or `client_uri`.
- Turn client metadata into authority to expand Campsite's configured OAuth
  scopes or grant types.
- Remove DCR, migrate existing DCR applications, or decide its eventual removal
  date beyond the minimum compatibility boundary.
- Establish a domain allowlist or a new client-attestation system in this
  change.

## Decisions

### Decision 1 — route URL client IDs through one resolver; leave existing IDs unchanged

A single client resolver sits at the Doorkeeper application lookup boundary used
by both authorization and token exchange. Ordinary UIDs continue through
`OauthApplication.kept` exactly as today. A syntactically eligible CIMD ID goes
through the metadata resolver and returns a Doorkeeper-compatible public-client
identity with the validated redirect URI set and server-allowed scopes.

Eligibility is intentionally narrow: absolute HTTPS URL, authority present, no
userinfo or fragment, and a path component. A string that looks like a URL but
fails eligibility is rejected as an invalid client; it does not fall through to
an outbound request. The fetched document does not expand Campsite's configured
grant types or scopes.

The same resolved identity must be used when issuing the authorization grant and
when redeeming it. Resolving only in the custom authorization controller is
insufficient because Doorkeeper performs its own client lookup during preflight
and token exchange.

- *Alternative considered:* create CIMD applications through `POST
  /oauth/register`. Rejected: CIMD's client ID is the metadata URL and requires
  no registration request; forcing DCR would defeat the new mechanism.
- *Alternative considered:* special-case only the consent controller. Rejected:
  token exchange would still reject the URL client ID or bind the grant to a
  different client.

### Decision 2 — use a fail-closed, SSRF-safe metadata fetcher

Only the client-ID URL itself is fetched. The fetcher uses verified TLS, allows
HTTP GET over HTTPS only, sends no Campsite credentials or ambient cookies, and
applies strict connection/read/total timeouts. It limits redirect count,
revalidates every redirect target, bounds the response to 5 KiB before JSON
parsing, and accepts a JSON object only.

Before each network connection, resolve the hostname and reject the request if
any candidate address is private, loopback, link-local, multicast, unspecified,
reserved, or otherwise non-public. Connect only to an address that passed that
check while preserving the original hostname for TLS and HTTP Host validation;
repeat the process for redirects. This prevents a pre-check followed by a fresh,
attacker-controlled DNS lookup from becoming a rebinding bypass.

No redirect may downgrade to HTTP, introduce userinfo, or reach a disallowed
address. Fetch failures and policy rejections abort authorization without
falling back to a similarly named persisted client.

- *Alternative considered:* use the application's ordinary HTTP client with a
  scheme check. Rejected: a scheme check alone does not cover private DNS
  answers, rebinding, redirect pivots, or response exhaustion.

### Decision 3 — validate the normative metadata and exact redirect before consent

The document must contain non-empty `client_id`, `client_name`, and
`redirect_uris`; `client_id` must be byte-for-byte equal to the requested URL;
and `redirect_uris` must be an array of valid URI strings. The authorization
request proceeds only when its `redirect_uri` exactly matches one array entry.
The existing OAuth and MCP communication-security rules still apply to redirect
URIs (HTTPS, with the permitted loopback development exception); CIMD does not
relax them.

Consent uses the validated `client_name`, but also visibly presents the client-ID
hostname and redirect hostname so a friendly name cannot hide the destination.
Optional metadata is ignored unless a later reviewed change gives it semantics.

- *Alternative considered:* prefix, origin-only, or wildcard redirect matching.
  Rejected: the CIMD and OAuth security contracts require exact registered
  redirect matching.

### Decision 4 — cache valid documents only and keep freshness policy bounded

The resolver may cache a successfully fetched and validated document. It honors
HTTP freshness metadata but clamps freshness to configured lower/upper bounds so
an attacker cannot force a fetch on every authorization request or make stale
metadata effectively permanent. Cache keys use the exact client-ID URL. Invalid
documents, network failures, non-2xx responses, and policy rejections are never
cached as client metadata.

Redirect validation always reads from the same validated cached document used to
construct the client identity. Expiry causes a refetch and complete revalidation;
there is no stale-if-error authorization path.

- *Alternative considered:* persist the first document indefinitely. Rejected:
  the client controls its metadata and HTTP freshness, and redirect revocation
  must eventually take effect.
- *Alternative considered:* negative caching. Rejected for the initial rollout:
  it makes transient client-host failures indistinguishable from invalid
  clients and complicates recovery.

### Decision 5 — DCR remains an independent fallback through the compatibility window

The existing DCR route, `OauthApplication` behavior, discovery
`registration_endpoint`, and Rack::Attack throttle remain operational. CIMD
does not auto-convert, invalidate, or re-key existing applications. DCR cannot
be removed before 2027-07-28, and removal after that date requires its own usage
evidence, migration plan, OpenSpec change, and release communication.

This mirrors MCP client priority: pre-registration when available, then CIMD
when advertised, then DCR fallback.

### Decision 6 — RFC 9207 support is atomic with its metadata advertisement

Every authorization response emitted by the supported authorization-code flow,
including successful and OAuth error responses, includes `iss` equal to the RFC
8414 metadata `issuer`. Only once this is true does discovery expose
`authorization_response_iss_parameter_supported: true`. Tests cover both query
and any enabled form-post response construction as well as non-redirected error
serialization, so an error path cannot be silently omitted.

Doorkeeper 5.6.9 does not expose evident native support in the installed source.
The implementation starts with an extension-point proof and chooses the
narrowest supported route: a documented Doorkeeper hook/override if stable, or
a separately reviewed dependency upgrade if not. It must not monkey-patch an
opaque private method without characterization tests.

### Decision 7 — advertise CIMD last and fail closed operationally

The discovery flag is the client-visible launch switch: it is added only after
the resolver, token exchange, SSRF controls, cache, consent identity, and tests
are deployed. Structured metrics distinguish cache hit/miss, fetch failure,
policy rejection, invalid document, redirect mismatch, and successful CIMD
authorization without logging authorization codes, client secrets, tokens, or
document bodies.

## Risks / Trade-offs

- **SSRF or DNS rebinding through attacker-controlled client IDs** → Centralize
  fetching; validate and pin public addresses on every hop; bound redirects,
  time, bytes, and parsing; test private/reserved IPv4 and IPv6 targets.
- **A cached redirect remains valid after the client removes it** → Honor HTTP
  freshness with a finite upper bound; never serve stale metadata after expiry.
- **Doorkeeper assumes a persisted application foreign key** → Prove the full
  authorization/grant/token lookup path before implementation and choose a
  representation that preserves grant binding and revocation semantics.
- **Friendly-name phishing or localhost impersonation** → Show the client-ID and
  redirect hostnames during consent in addition to `client_name`; consider a
  later trust/attestation policy if abuse appears.
- **Advertising support before every path works** → Add both RFC 8414 flags only
  after end-to-end success/error and token-redemption tests pass.
- **DCR clients are stranded by premature cleanup** → Preserve the endpoint and
  stored applications through the minimum window; make removal a separate
  change.

## Migration Plan

1. Characterize Doorkeeper's authorization, grant persistence, token exchange,
   error response, and PKCE paths for a URL client ID; record the supported
   extension points in this design before implementation.
2. Implement and test the fetch/validation/cache layer without advertising CIMD.
3. Integrate CIMD client resolution through authorization and token exchange,
   then add consent identity and RFC 9207 response behavior.
4. Deploy the code with DCR unchanged. Enable the discovery indicators only
   after production-safe SSRF policy and end-to-end tests pass.
5. Roll back by removing the CIMD and RFC 9207 discovery indicators first, then
   disabling CIMD resolution. DCR and existing `OauthApplication` clients remain
   the working fallback throughout.

## Open Questions

- What cache store and minimum/maximum freshness bounds best fit Campsite's
  deployment? The protocol requires cache-header-aware behavior but does not set
  deployment TTLs.
- Should CIMD resolution inherit the existing `mcp_server` Flipper kill-switch,
  use a separate rollout flag, or rely only on the discovery indicator? This is
  an operational rollout choice; all options preserve the behavior contract.
- Which Doorkeeper-compatible representation should bind a CIMD client to access
  grants/tokens: a controlled persisted application row or a supported transient
  adapter plus explicit grant binding? The extension-point spike must choose the
  option that preserves PKCE, token redemption, revocation, and metadata refresh.
- Can RFC 9207 be added through a stable Doorkeeper 5.6.9 extension point, or is a
  dependency upgrade safer? `Gemfile.lock` alone cannot answer this, and the
  installed 5.6.9 response source shows no native `iss` field.
- Should Campsite initially accept every public HTTPS CIMD domain or add a trust
  policy before advertising support? Domain policy is optional in the CIMD
  draft; SSRF safety and explicit consent identity remain mandatory either way.
