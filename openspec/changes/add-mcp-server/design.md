## Context

Campsite's backend is a Rails 8.1 API (`api/`) using MySQL/trilogy, Devise +
Doorkeeper for auth, Pundit for authorization, and Blueprinter for serialization.
It already runs a **full Doorkeeper OAuth2 provider** (`config/initializers/
doorkeeper.rb`): authorization-code grant, polymorphic resource owner, a custom
authorizations controller, an `OauthApplication`/`AccessToken`/`AccessGrant`
model set, and a scope list (`read_organization`, `read_user`, `write_post`,
`write_project`, etc.). The `/api/v1` controllers already cover posts, comments,
messages, notes, projects, and organizations, each guarded by Pundit policies.

The user's target experience is: connect Campsite from an LLM client (Claude)
exactly like the Notion and PostHog connectors. Those are **remote MCP servers**
reached over HTTP and authorized with OAuth — the client supplies discovery and
PKCE; the server proves identity and runs tools. No model inference happens on
the server side.

Constraints: deploy is Hatchbox (not Fly — Fly tasks are dead). New libraries
must be pinned to the latest stable at install time (user rule). Minitest, not
RSpec. Lint via rubocop-shopify with a `no_focus` cop.

## Goals / Non-Goals

**Goals:**
- A remote MCP server **mounted in the Rails API** at a stable HTTP path (`/mcp`),
  reusing existing auth, policies, serializers, and models.
- Read **and** write tools over the core domain, each running through the same
  Pundit authorization as the REST API.
- A connect flow that works from Claude's connector UI with **no hand-provisioned
  credentials** — OAuth discovery metadata + dynamic client registration on top
  of the existing Doorkeeper provider, with PKCE and a single `mcp` scope.

**Non-Goals:**
- A standalone MCP microservice (rejected below).
- Any LLM/inference call from the server.
- Hard-delete / bulk-destructive tools in the first cut.
- Reworking the existing Doorkeeper config or REST API contracts.
- Touching upstream Fly deploy tooling.

## Decisions

### Decision 1 — Mount in Rails, do not build a standalone service
Mounting reuses Doorkeeper auth, `Current` context, Pundit policies, and
Blueprinter serializers in-process. A standalone server would have to re-implement
auth, re-call the REST API over the network (extra hop + token plumbing), and
drift from policy changes. The user asked us to recommend; the existing OAuth +
domain layer makes mounting clearly simpler and safer.
- *Alternative considered:* separate Ruby/Rack service calling `/api/v1` with a
  service token. Rejected: duplicates auth, weaker per-user authorization, more
  infra.

### Decision 2 — MCP gem + Streamable HTTP transport, mounted as a Rack endpoint
Use a maintained Ruby MCP library to handle the JSON-RPC framing, `initialize`/
`tools/list`/`tools/call`, and the Streamable HTTP transport, mounted in
`config/routes.rb` (e.g. `mount` a Rack app or route to a controller at `/mcp`).
Candidates: the official `mcp` Ruby SDK and `fast-mcp` (ships Rack/Rails mounting
+ SSE/HTTP). **At implementation time, evaluate both and pick the one with clean
Rack mounting + Streamable HTTP + active maintenance, and install the latest
stable version** (per the add-latest-library rule). The transport choice must be
the modern Streamable HTTP endpoint (single `/mcp` path), since that is what
current remote connectors negotiate.
- *Alternative considered:* hand-rolling JSON-RPC. Rejected: needless surface area
  and spec-drift risk.

### Decision 3 — Authn: reuse Doorkeeper bearer tokens, gate with an `mcp` scope
The `/mcp` endpoint validates the bearer access token via Doorkeeper, requires
the `mcp` scope, then sets `Current.user` / organization membership from the
token's resource owner — the same pattern `Api::V1::BaseController` already uses.
Individual write tools additionally require the matching `write_*` scope. Add
`mcp` to `optional_scopes` in the Doorkeeper initializer.
- *Alternative considered:* a bespoke personal-access-token model. Rejected:
  Doorkeeper already issues per-user scoped tokens; a connector needs the OAuth
  flow anyway (Decision 4), so PATs add a parallel auth path for no gain.

### Decision 4 — Authz/connect: add OAuth discovery + DCR on top of Doorkeeper
To match the Notion/PostHog UX, the client must self-discover and self-register.
Add three things the connector spec requires that Doorkeeper does not serve out
of the box:
1. `/.well-known/oauth-protected-resource` (RFC 9728) describing `/mcp` and
   pointing at the auth server; the `401` from `/mcp` carries a
   `WWW-Authenticate` with a `resource_metadata` pointer.
2. `/.well-known/oauth-authorization-server` (RFC 8414) advertising Doorkeeper's
   authorize/token/registration endpoints, `S256` PKCE, grant types, and
   `scopes_supported` incl. `mcp`.
3. Dynamic Client Registration (RFC 7591) creating an `OauthApplication` from the
   client's POST and returning `client_id`/`client_secret`.
The authorization-code + PKCE flow and consent screen are already implemented by
Doorkeeper's custom authorizations controller.
- *Alternative considered:* pre-register a single shared OAuth app and hand the
  user a client id. Rejected: not the Notion/PostHog UX, and per-client
  registration is what MCP clients expect.

### Decision 5 — Tools wrap controllers/services, not duplicate them
Each tool is a small class (name, description, JSON-Schema input) that builds the
same params and calls the same model/service path the matching controller uses,
authorizing with the same Pundit policy and serializing with the same Blueprinter
serializer (or a trimmed subset). Start with a focused catalog:
- **Read:** `list_organizations`, `list_projects`, `list_posts` (filter by
  project), `search_posts`, `read_post` (+comments), `list_message_threads`,
  `read_messages`, `list_notes`, `read_note`.
- **Write:** `create_post`, `add_comment` (post/note), `add_reaction`.
Reads are bounded/paginated. No delete/bulk tools in v1.

## Risks / Trade-offs

- **Connector OAuth spec is finicky (discovery + DCR + PKCE must all line up)** →
  Validate against the actual Claude connector flow early; lean on RFC 9728/8414/
  7591 conformance and reuse Doorkeeper's existing PKCE-capable code path rather
  than custom token logic.
- **DCR creates `OauthApplication` rows from anonymous clients (abuse/spam)** →
  Constrain registration (allowed redirect URI schemes, optional rate limit), and
  rely on the human consent + login step before any token is issued. Revisit
  software-statement / allowlisting if abused.
- **A write tool could mutate data on the user's behalf with weak confirmation** →
  Keep v1 additive-only (no deletes), require `write_*` scopes, give tools clear
  names/descriptions so the client surfaces an accurate confirmation, and run
  every call through Pundit.
- **In-process MCP coupled to the API's deploy/scaling** → Acceptable: it is a
  thin endpoint reusing existing logic; if load demands it later, the tool layer
  is already factored to extract.
- **MCP library/transport churn** → Pin a maintained gem at latest stable, isolate
  it behind our tool registry + a thin mount so swapping transports is local.
- **Mounting a new public route on Hatchbox/nginx** → Confirm `/mcp` and the
  `.well-known` paths are routed/proxied through to Rails and not shadowed.

## Migration Plan

1. Add the MCP gem (latest stable) and an `mcp` optional scope in the Doorkeeper
   initializer.
2. Add the `.well-known` discovery endpoints + DCR endpoint backed by
   `OauthApplication`.
3. Mount the `/mcp` endpoint with token+scope auth setting `Current` context.
4. Implement the tool registry and the read tools, then the write tools.
5. Test end-to-end against the Claude connector flow in a staging org; verify
   consent, scopes, and Pundit denial paths.
6. Roll out behind a Flipper flag if a gradual enable is wanted; the route can be
   disabled by flag/feature without affecting the REST API.

**Rollback:** remove/disable the `/mcp` route and the `.well-known`/DCR endpoints;
the existing REST API and Doorkeeper provider are unchanged. Drop the `mcp` scope
last (revoking issued connector tokens).

## Open Questions

- Which MCP gem wins on Rack-mount + Streamable HTTP + maintenance (resolve at
  task start by spiking both)?
- Should DCR be open or gated behind an allowlist / approval for production?
- Multi-org users: does a single `mcp` token act across all the user's orgs, or do
  we scope a connection to one organization at connect time?
- Do we want a Flipper flag gating availability for the initial rollout?
