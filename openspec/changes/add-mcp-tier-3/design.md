## Context

The `mcp` gem (`~> 0.22.0`) supports far more than tools: `MCP::Server.new` accepts
`prompts:`, `resources:`, `resource_templates:`, and a `capabilities:` hash, and the
server already routes `resources/list`, `resources/templates/list`, `resources/read`,
`resources/subscribe`, `resources/unsubscribe`, `prompts/list`, `prompts/get`, and
the matching `notifications/{resources,prompts}/*` methods (verified in
`mcp/server.rb` and `mcp/methods.rb`). Today `McpServer.build` passes only `tools:`,
so none of these capabilities are advertised. Tier 3 turns the three remaining
protocol surfaces on.

All tool work continues the `McpTool` pattern from the prior tiers
(`organization_context!` → `require_scope!` → `authorize!` → serialize →
`data_response`). Tests live in `test/controllers/mcp_controller_test.rb`.

### Phasing — three changes' worth of scope in one proposal

Phases A (attachments), B (resources), and C (prompts) share no code and can ship in
any order. They are grouped because the prior changes deferred them together as
"Tier 3". At implementation time each phase MAY be split into its own OpenSpec change
(`add-mcp-attachments`, `add-mcp-resources`, `add-mcp-prompts`); the task list is
ordered C → B → A → subscriptions by ascending risk so the safe wins land first.

## Decisions

### Decision A1 — mirror the REST two-step upload as the canonical path
The web app uploads in two steps: `GET …/presigned-fields` to mint an S3 POST policy,
upload bytes straight to S3, then `POST …/attachments` with the returned `file_path`
(the S3 key) and `file_type`. MCP exposes the same two steps as `create_upload` and
`attach_file`. This keeps the contract identical to REST, puts **no file bytes
through the MCP/JSON-RPC transport**, and inherits the existing
`content_length_range`/`content_type`/3-minute-expiry guards from
`PresignedPostFields.generate`. `create_upload` writes nothing in Campsite (it only
mints S3 credentials), so it gates on `mcp` only; `attach_file` creates the
`Attachment` and links it to a subject, so it requires that subject's write scope and
authorizes the subject `:update?` (matching `Posts::AttachmentsController#create`).

### Decision A2 — `upload_attachment` is a bounded server-side convenience, not the default
The canonical path (A1) assumes the client can perform a multipart POST to S3 with
the exact presigned fields. Many MCP clients (including agent runtimes whose only
egress is the MCP transport) cannot — yet the headline Tier 3 use case is an
**agent-produced artifact**, where the agent already holds the bytes. So
`upload_attachment` accepts inline base64 `content` + `file_type` + subject, uploads
server-side to S3 via the same presigned policy, and creates+links the attachment in
one call. Trade-off: bytes travel through the JSON-RPC transport and Rails memory, so
the tool enforces a **hard size cap** (`MAX_INLINE_UPLOAD_BYTES`, a few MB) and
rejects anything larger with a `ToolError` pointing at `create_upload` +
`attach_file`. base64 inflation (~33%) is counted against the cap. Same scope and
`:update?` authorization as `attach_file`.

### Decision A3 — attachment subject is polymorphic, write scope follows the subject
`attach_file`/`upload_attachment` take a `subject_type` (`post`/`note`/`comment`/
`message`) + `subject_id`, resolved within the org, and create through that subject's
`attachments` association. The required write scope follows the subject:
`write_post` for post/comment, `write_note` for note, `write_message` for message —
no new scope. Authorization is the subject's existing policy
(`:update?` for posts/notes, the comment's subject `:update?`, the message thread's
write policy), so a member can only attach where they could already attach via REST.
Attachment **delete** and **reorder** are deliberately excluded (additive-only, as in
prior tiers).

### Decision B1 — resources reuse read serializers and read scopes; no new read surface
A resource read is the same data a `read_*` tool returns. `resources/read` parses a
`campsite://{org_slug}/{type}/{public_id}` URI, resolves the org membership exactly
like `organization_context!`, loads the record under `policy_scope`, and renders the
existing serializer (`PostSerializer`/`NoteSerializer`/`MessageThreadSerializer`).
Unknown URI → not-found error; forbidden record → authorization error. Gating uses
the existing read scope for that type. Resources add **addressability and
browsability**, not new data or new authorization.

### Decision B2 — static `resources` list is bounded; arbitrary entities go through templates
`resources/list` advertises only a small, bounded set (e.g. the connecting user's N
most-recent posts/notes across orgs) so the catalog never unbounded-paginates the
whole workspace. Any specific entity is addressable via the advertised
`resource_templates` (`campsite://{org_slug}/posts/{public_id}`, etc.) and read
directly — the client does not need it to appear in `list` first. `list` is for
discovery; templates are for addressing.

### Decision B3 — subscriptions are spiked before they are promised
`resources/subscribe` + `notifications/resources/updated` require the server to push
to the client **after** the request completes, which needs a live server→client
stream. Campsite's remote MCP runs over Streamable HTTP behind Hatchbox/nginx with
stateless Doorkeeper bearer auth; it is **not yet established** that a long-lived SSE
stream survives that path, nor that a Sidekiq/Pusher change event can be bridged onto
the MCP session. So subscriptions are specified as a requirement but **gated on a
spike** (tasks 4.x): confirm the transport holds a stream end-to-end on staging
before wiring `resources_subscribe_handler` to a change source. If the spike fails,
ship resources **without** subscriptions (do not advertise `resources.subscribe`) and
re-defer the subscription requirement. Resource change events, if built, should bridge
the existing Pusher/`*_stale` invalidation signals rather than introduce a new bus.

### Decision C1 — prompts are static templates, never mutate
Prompts returned by `prompts/get` are message templates that *instruct* the client to
call existing tools; the prompt handler itself performs no Campsite write and runs no
inference. It may read (e.g. interpolate the user's name from `whoami`) but its output
is text/messages. This keeps prompts safe to expose under `mcp` alone and keeps all
mutation behind the already-scoped tools.

### Decision C2 — wire capabilities explicitly in `McpServer.build`
`McpServer.build` passes `prompts:` and `resources:` (and `resource_templates:`) and
an explicit `capabilities:` hash: `{ tools: {}, prompts: { listChanged: true },
resources: { listChanged: true } }`, adding `subscribe: true` to `resources` **only**
if Decision B3's spike passes. `resources_read_handler` (and the subscribe handlers,
conditionally) are registered on the per-request server so they resolve under the
authenticated `server_context`, never a shared one.

## Risks / Trade-offs

- **Inline upload size (A2)** — capping inline base64 protects the transport but
  means large artifacts still require an S3-capable client. Documented in the tool
  description and the error message; not a regression (matches the web app's own
  direct-to-S3 model).
- **Resource read amplification (B1)** — resources are another doorway to the same
  reads; mitigated by reusing the exact Pundit scope per type, so they expose nothing
  the read tools don't.
- **Subscriptions may not ship (B3)** — explicitly de-risked by the spike gate;
  resources are valuable without them.
- **Prompt drift (C1)** — templates referencing tool names can rot if tools are
  renamed; mitigated by a test asserting each prompt's referenced tool names exist in
  `McpToolRegistry`.

## Migration / Rollout

No data migration. No new OAuth scope (attachments reuse `write_*`, resources reuse
`read_*`, prompts use `mcp`). All additions are advertised via new server
capabilities; existing tool-only connectors are unaffected until they call the new
tools or request resources/prompts. If `/mcp` is behind the rollout Flipper flag
(`add-mcp-server` 6.1), Tier 3 inherits it. Subscriptions ship only if the transport
spike passes; otherwise the `resources.subscribe` capability is not advertised.
