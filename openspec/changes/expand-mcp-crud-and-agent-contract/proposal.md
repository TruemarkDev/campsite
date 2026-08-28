## Why

Campsite's MCP server exposes a useful additive agent loop, but its catalog is not
CRUD-complete and its behavioral contract is mostly human-only prose. Connected
agents cannot edit or withdraw their own comments and messages, manage follow-ups,
inspect or update projects, manage attachments, or safely edit collaborative note
bodies. `tools/list` also omits output schemas and MCP safety annotations, so clients
must infer mutability and result shapes from descriptions.

The user approved this change as an explicit stewardship exception. It expands MCP
through existing Rails domain services and Pundit policies without adding a model,
dependency, authorization bypass, hard deletion, or bulk mutation.

## What Changes

- Publish a machine-readable contract for every tool: output schema, standard MCP
  safety annotations, required scopes, category, and stable Campsite metadata.
- Expose a versioned agent guide as `campsite://docs/agent-guide` and keep the human
  tool catalog synchronized with the runtime registry.
- Add bounded CRUD for comments, follow-ups, reactions, messages, projects,
  favorites, read state, and project pins.
- Add guarded content lifecycle operations for projects, posts, notes, and
  attachments, always reusing current Pundit/domain behavior.
- Add collaborative note-body editing through the existing short-lived
  `AgentSyncGrant` and replica-safe sync-server agent-edit facade.
- Return structured error codes and resulting serialized state rather than vague
  success text.

## Capabilities

### Modified Capabilities

- `mcp-tools`: adds CRUD/lifecycle tools and complete machine-readable contracts.
- `mcp-resources`: adds a static, versioned agent guide resource.

## Impact

- Rails MCP registry/base/resource layers and focused MCP tests.
- New thin tool wrappers under `api/app/mcp/mcp_tools/`.
- Existing OAuth scopes (`mcp`, `write_post`, `write_message`, `write_note`, and
  `write_project`) remain authoritative.
- Existing Pundit policies, serializers, discard/archive behavior, and the
  replica-safe note-edit facade remain authoritative.
- Excluded: project membership, public visibility/sharing, integrations, OAuth
  applications, data exports, raw sync state, arbitrary URLs/shell, bulk actions,
  and permanent deletion.
