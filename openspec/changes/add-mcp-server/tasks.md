## 1. Spike & dependency

- [ ] 1.1 Spike the official `mcp` Ruby SDK vs `fast-mcp`: confirm clean Rack/Rails mounting, Streamable HTTP transport, and active maintenance; pick one
- [ ] 1.2 `bundle add <chosen-mcp-gem>` at latest stable; commit Gemfile/Gemfile.lock
- [ ] 1.3 Add `mcp` to `optional_scopes` in `config/initializers/doorkeeper.rb` and confirm scope description/labels for consent

## 2. OAuth discovery & dynamic client registration

- [ ] 2.1 Add `/.well-known/oauth-protected-resource` (RFC 9728) describing `/mcp` and pointing at the Doorkeeper auth server
- [ ] 2.2 Add `/.well-known/oauth-authorization-server` (RFC 8414) advertising authorize/token/registration endpoints, `S256` PKCE, grant types, and `scopes_supported` incl. `mcp`
- [ ] 2.3 Add a Dynamic Client Registration endpoint (RFC 7591) that creates an `OauthApplication` and returns `client_id`/`client_secret`; constrain redirect URI schemes
- [ ] 2.4 Verify the existing Doorkeeper authorization-code + PKCE flow and consent screen name Campsite and the requested scopes
- [ ] 2.5 Tests for discovery payloads, DCR creation, and redirect-URI validation

## 3. MCP endpoint & auth

- [ ] 3.1 Mount the MCP server at `/mcp` (Streamable HTTP) in `config/routes.rb`
- [ ] 3.2 Authenticate each request via Doorkeeper bearer token, require the `mcp` scope, and set `Current.user` / organization membership from the token's resource owner
- [ ] 3.3 Return 401 with a `WWW-Authenticate` header carrying the `resource_metadata` pointer when unauthenticated
- [ ] 3.4 Implement the `initialize` handshake (protocol version, server info, `tools` capability)
- [ ] 3.5 Wire `tools/list` and `tools/call` to the tool registry, returning tool-level error results for unknown tool / invalid input
- [ ] 3.6 Tests: handshake, missing/invalid token (401), token without `mcp` scope (denied), unknown tool error

## 4. Tool registry & read tools

- [ ] 4.1 Build a tool registry + base tool abstraction (name, description, JSON-Schema input, `call` running under Pundit and serializing via Blueprinter)
- [ ] 4.2 `list_organizations`, `list_projects`
- [ ] 4.3 `list_posts` (filter by project, bounded/paginated) and `search_posts`
- [ ] 4.4 `read_post` (with comments)
- [ ] 4.5 `list_message_threads`, `read_messages`, `list_notes`, `read_note`
- [ ] 4.6 Tests per read tool incl. a Pundit-denial case proving no authorization bypass

## 5. Write tools

- [ ] 5.1 `create_post` (requires `write_post` scope; same validations as the REST API)
- [ ] 5.2 `add_comment` for post and note (requires write scope)
- [ ] 5.3 `add_reaction`
- [ ] 5.4 Confirm no delete/bulk-destructive tool is registered or advertised
- [ ] 5.5 Tests: successful writes, write blocked without `write_*` scope, Pundit-denial path

## 6. End-to-end, rollout & docs

- [ ] 6.1 (Optional) Gate `/mcp` and discovery routes behind a Flipper flag for gradual rollout
- [ ] 6.2 Verify routing/proxy: `/mcp` and `.well-known/*` reach Rails through Hatchbox/nginx
- [ ] 6.3 End-to-end test the Claude connector flow against a staging org: add connector → sign in → consent → list tools → call a read tool → call a write tool
- [ ] 6.4 Run `bundle exec rubocop` and `bin/rails test`; fix lint/test failures
- [ ] 6.5 Document connecting Campsite from Claude (URL to add, scopes, what tools exist) in the API docs/README
