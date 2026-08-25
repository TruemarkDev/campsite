## 1. Resolve integration and rollout decisions

- [x] 1.1 Characterize Doorkeeper 5.6.9's client lookup, authorization grant,
      token redemption, PKCE, revocation, success response, and error response paths
      with tests; identify supported extension points for URL client IDs and RFC 9207
- [x] 1.2 Choose and document the CIMD client representation (controlled
      persisted application or supported transient adapter), proving it preserves
      grant/token binding without treating metadata as a client secret
- [x] 1.3 Choose and document the cache store, lower/upper freshness bounds,
      rollout gating (`mcp_server`, a separate flag, or discovery-only), and initial
      domain trust policy before implementation
- [x] 1.4 Decide whether RFC 9207 can use a stable Doorkeeper 5.6.9 extension or
      requires a separately reviewed dependency upgrade; update `design.md` with the
      verified route

## 2. Metadata retrieval and validation

- [x] 2.1 Implement one CIMD URL eligibility/parser boundary: absolute HTTPS,
      authority and path present, no userinfo or fragment, with invalid URL-shaped
      client IDs rejected without a network request
- [x] 2.2 Implement the credential-free metadata fetcher with verified TLS,
      public-address resolution and connection pinning, redirect rejection,
      time/5-KiB response limits, and bounded JSON parsing
- [x] 2.3 Validate required `client_id`, `client_name`, and `redirect_uris`
      metadata; require exact client-ID and redirect-URI matches; ignore optional
      asset/key URLs rather than fetching them
- [x] 2.4 Cache only valid documents using exact-URL keys and HTTP freshness
      clamped to the chosen bounds; refetch after expiry and fail closed without
      stale or negative-cache authorization
- [x] 2.5 Add secrets-safe metrics/logging for cache outcomes, fetch failures,
      SSRF-policy rejections, invalid documents, redirect mismatches, and successful
      resolution

## 3. Doorkeeper authorization and token integration

- [x] 3.1 Route persisted client IDs through the unchanged
      `OauthApplication.kept` path and eligible URL IDs through the centralized CIMD
      resolver at every Doorkeeper client lookup used by authorization and token
      exchange
- [x] 3.2 Bind authorization grants and access tokens to the same validated CIMD
      client identity while preserving S256 PKCE, configured scopes, token
      redemption, and revocation behavior
- [x] 3.3 Update consent for CIMD requests to display validated `client_name`,
      client-ID host, redirect host, and requested scopes before approval
- [x] 3.4 Return safe OAuth errors for fetch, validation, and redirect failures;
      never redirect an error or success response to an unvalidated URI

## 4. Discovery and authorization-response issuer

- [x] 4.1 Add RFC 9207 `iss`, equal to the RFC 8414 `issuer`, to every successful
      and error authorization response in each enabled response mode or error
      serialization path
- [x] 4.2 Advertise
      `authorization_response_iss_parameter_supported: true` only when all covered
      response paths include `iss`
- [x] 4.3 Advertise `client_id_metadata_document_supported: true` only after CIMD
      authorization and token redemption are enabled end to end; retain the DCR
      `registration_endpoint`

## 5. Backward compatibility and documentation

- [x] 5.1 Keep `POST /oauth/register`, its Rack::Attack throttle, existing DCR
      credentials, and pre-registered clients unchanged; add a regression test for
      DCR registration plus authorization/token redemption
- [x] 5.2 Update `api/docs/mcp_server.md` with CIMD discovery/flow, DCR fallback
      and the no-earlier-than-2027-07-28 compatibility boundary, cache/fetch
      operating notes, rollout/rollback, and RFC 9207 behavior

## 6. Security, behavior, and quality gates

- [x] 6.1 Test valid CIMD authorization through code redemption, exact
      client-ID/redirect matching, required-field/JSON/size failures, cache
      hit/expiry/refetch/failure behavior, and no stale authorization
- [x] 6.2 Test SSRF defenses for private/reserved IPv4 and IPv6, mixed DNS
      answers, DNS rebinding, redirects, userinfo,
      timeouts, oversized bodies, and optional metadata URLs that must not be fetched
- [x] 6.3 Test consent identity, CIMD and RFC 9207 discovery gating, `iss` on
      success and error responses, persisted-client parity, and DCR compatibility
- [x] 6.4 Run the focused OAuth controller/service tests, full relevant Rails
      test slice, RuboCop on touched Ruby files, and strict OpenSpec validation; do
      not advertise support until all gates pass
