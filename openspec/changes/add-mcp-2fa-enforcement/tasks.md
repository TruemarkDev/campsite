## 1. Enforcement

- [x] 1.1 In `McpTool#organization_context!`, after resolving the organization,
      raise a `ToolError` when `organization.enforce_two_factor_authentication?` and
      `!user.otp_enabled?` — before setting `Current` or doing any work

## 2. Tests & gates

- [x] 2.1 A tool call in an org that enforces 2FA, by a user without 2FA, returns a
      tool error and performs no work
- [x] 2.2 The same call succeeds when the user has 2FA enabled
- [x] 2.3 Orgs that do not enforce 2FA are unaffected (existing tests still pass)
- [x] 2.4 Run `bundle exec rubocop` and `bin/rails test test/controllers/mcp_controller_test.rb`; fix failures
