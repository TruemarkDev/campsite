## ADDED Requirements

### Requirement: MCP enforces organization two-factor authentication

The MCP server SHALL enforce an organization's two-factor-authentication policy on
every org-scoped tool call, matching the REST API. WHEN an organization has 2FA
enforcement enabled and the acting user has not enabled two-factor authentication,
the server SHALL deny the tool call with an error and perform no read or write. The
check SHALL occur per resolved organization at tool-call time (a single connection
is multi-org), and SHALL use the same predicates as the REST API
(`Organization#enforce_two_factor_authentication?`, `User#otp_enabled?`).

#### Scenario: User without 2FA is blocked in a 2FA-enforcing org

- **WHEN** a user whose account has not enabled 2FA calls any org-scoped tool for an organization that enforces 2FA
- **THEN** the tool returns an error indicating two-factor authentication is required and performs no read or write

#### Scenario: User with 2FA proceeds normally

- **WHEN** a user who has enabled 2FA calls a tool for a 2FA-enforcing organization they belong to
- **THEN** the tool executes normally

#### Scenario: Non-enforcing organizations are unaffected

- **WHEN** a user calls a tool for an organization that does not enforce 2FA
- **THEN** the tool executes normally regardless of the user's 2FA status
