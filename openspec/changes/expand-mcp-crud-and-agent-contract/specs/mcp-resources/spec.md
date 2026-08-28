## ADDED Requirements

### Requirement: MCP publishes a runtime agent guide

The server SHALL list and read `campsite://docs/agent-guide` as versioned Markdown
covering identity, scopes, pagination, mentions, mutation safety, error recovery,
collaborative note editing, and excluded operations.

#### Scenario: Agent reads operating guidance

- **WHEN** a connected client reads `campsite://docs/agent-guide`
- **THEN** it receives the current guide without requiring an organization slug and
  without exposing organization data
