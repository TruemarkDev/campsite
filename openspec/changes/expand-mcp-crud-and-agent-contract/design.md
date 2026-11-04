## Context

The current registry intentionally favored additive writes. Campsite now has enough
agent usage to require safe parity for routine correction and lifecycle operations.
The REST surface already contains the relevant authorization and domain logic, while
the MCP Ruby SDK supports `outputSchema` and standard tool annotations.

## Decisions

### A-1 — Domain logic and authorization stay outside MCP tools

Each tool SHALL resolve organization context, require the existing OAuth scope,
authorize the same record/action through Pundit, and call the same model/service path
as REST. Tools SHALL NOT reproduce permission logic.

### A-2 — Tool contracts are runtime metadata

Every registered tool SHALL advertise an object output schema and standard MCP
annotations. Registry metadata SHALL state required scopes and category. A registry
test SHALL fail on missing metadata.

### A-3 — Destructive means state-removing, even when recoverable

Discard, archive, cancellation, removal, and attachment destruction SHALL set
`destructiveHint: true`. The annotation is advisory; OAuth and Pundit enforcement
remain mandatory. Hard-delete and bulk tools SHALL remain absent.

### A-4 — Agent guidance is available over MCP

The canonical runtime guide SHALL be readable at `campsite://docs/agent-guide`
without organization lookup. It SHALL describe identity, scopes, pagination,
mentions, errors, safe sequencing, note editing, and exclusions. Repository docs
SHOULD summarize and link to the same contract rather than inventing another API.

### A-5 — Collaborative note edits use the sync facade

`edit_note` SHALL issue a short-lived grant for the acting member, call
`AgentNoteEditor`, and revoke the grant in `ensure`. It SHALL expose only allowlisted
sync operations, fail closed when coordination is unavailable, and preserve the
existing active-human and replica coordination safeguards.

### A-6 — Privileged administration stays out

This change SHALL NOT expose membership administration, visibility/public sharing,
integration/OAuth administration, exports, raw collaboration state, hard deletion,
or bulk operations.

## Risks / Trade-offs

- More write tools increase accidental-action surface. Standard annotations,
  explicit names, scopes, Pundit, and narrow schemas reduce this risk.
- Generic output schemas are less precise than serializer-derived schemas. They are
  still an honest contract for normalized structured objects and can be refined
  incrementally without withholding safety metadata.
- Note editing depends on sync-server availability. Failure SHALL be returned as a
  tool error; MCP SHALL never fall back to direct HTML/state replacement.
