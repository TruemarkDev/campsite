## Why

The REST API enforces organization-level two-factor authentication on every
request via `Api::V1::BaseController`'s `require_org_two_factor_authentication`
before_action: if an organization has `enforce_two_factor_authentication?` set, a
user whose account has not enabled 2FA (`otp_enabled?` false) is blocked from every
read and write in that org.

The MCP server (`McpController`) does not run this check — it authenticates the
Doorkeeper bearer token, requires the `mcp` scope, then dispatches tools. So a user
without 2FA, holding an `mcp` token, can read and write through the connector in an
org that enforces 2FA, **bypassing the org's own security policy**. This bites in
particular when an org enables enforcement _after_ a token was already issued
(Doorkeeper tokens are long-lived). The MCP surface must not be a 2FA bypass.

## What Changes

- Enforce org-level 2FA in `McpTool#organization_context!`, the single chokepoint
  every org-scoped tool funnels through. After resolving the user's membership and
  the organization, if `organization.enforce_two_factor_authentication?` and the
  user is not `otp_enabled?`, the tool raises a `ToolError` (surfaced as a
  tool-level error) and performs no read or write — mirroring the REST behavior.
- Because a single MCP connection is multi-org, this is checked per resolved org at
  tool-call time (not as a controller before_action, since the org is unknown until
  the tool supplies `org_slug`).

## Capabilities

### Modified Capabilities

- `mcp-server`: org-scoped tool execution now enforces the organization's
  two-factor-authentication policy, matching the REST API, so the connector cannot
  be used to bypass enforced 2FA.

## Impact

- **New code**: a 2FA guard in `McpTool#organization_context!` (one place, covers
  all org-scoped tools at once); tests in `test/controllers/mcp_controller_test.rb`.
- **Reused, unchanged contracts**: `Organization#enforce_two_factor_authentication?`
  and `User#otp_enabled?` — the same predicates the REST before_action uses.
- **Behavioral change**: in orgs that enforce 2FA, users without 2FA now receive a
  tool error instead of a successful response. This is the intended REST parity.
- **Out of scope**: changing how 2FA is configured or enrolled; the non-security
  `BaseController` before_actions MCP also skips (figma/sync/cal integration-token
  restrictions — irrelevant to Doorkeeper tokens; last-seen/sentry bookkeeping).
