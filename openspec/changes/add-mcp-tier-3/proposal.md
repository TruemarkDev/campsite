## Why

Tiers 1 and 2 (`add-mcp-agent-loop-tools`, `add-mcp-coordination-tools`) gave a
connected agent a full work loop over **text**: identity, an inbox, notes, posts,
comments, projects, follow-ups. Everything an agent can read or write today is
HTML/Markdown carried inline in a tool call.

Tier 3 closes the three gaps that remain in the MCP protocol surface, all of which
were explicitly deferred by the earlier changes:

- **Artifacts.** An agent that produces a diagram, screenshot, CSV, or PDF has no
  way to attach it to a post, note, comment, or message. `create_post` etc. accept
  only `description_html`. The REST UI uploads files via presigned S3 POST then
  records an `Attachment`; MCP exposes neither step. Without this, agent output is
  text-only.
- **Resources.** MCP clients can attach server **resources** (addressable, readable
  URIs) as context and browse a catalog, independent of the tool-call loop. Campsite
  entities (posts, notes, threads) are natural resources, but the server advertises
  no `resources` capability today, so a client cannot say "add this Campsite post to
  the conversation" without round-tripping a `read_*` tool.
- **Prompts.** MCP **prompts** are reusable, server-authored templates a user can
  invoke from the client UI ("Triage my inbox", "Draft a standup from this week's
  posts"). They encode Campsite-specific workflows over the existing tools so users
  don't hand-write them. The server advertises no `prompts` capability today.

As in the prior tiers, no new domain logic and no model inference are introduced —
attachments reuse the existing presigned-upload + `Attachment` path under Pundit,
resources reuse the read serializers, and prompts are static templates that
reference existing tools.

## What Changes

Three independently-shippable additions. Each phase can be extracted into its own
change at implementation time (see `design.md`); they are grouped here because they
constitute "Tier 3" as deferred by the prior changes.

### A. Attachments / file upload (tools)

Expose the two-step REST upload contract over MCP, plus a convenience path:

- `create_upload` (org-scoped, no write scope) — return presigned S3 POST fields and
  the object `key` for a given `mime_type`, wrapping
  `organization.generate_post_presigned_post_fields`. The client uploads bytes
  directly to S3, exactly as the web app does. Read-only (mints credentials but
  writes nothing in Campsite), so gated on `mcp` only.
- `attach_file` (org-scoped, requires the subject's write scope) — create an
  `Attachment` from an uploaded `file_path` (S3 key) + `file_type` and link it to a
  `post` / `note` / `comment` / `message` subject, via the same
  `<subject>.attachments.create!` path and subject `:update?` authorization the REST
  attachment controllers use.
- `upload_attachment` (org-scoped, requires the subject's write scope) —
  **convenience** tool for agent-produced artifacts: accept small inline base64
  `content` + `file_type`, upload server-side to S3, and create+link the attachment
  in one call. Bounded by a hard size cap (transport-friendly); larger files MUST use
  `create_upload` + `attach_file`.

### B. MCP resources (+ optional subscriptions)

Advertise the `resources` capability and expose Campsite entities as addressable
URIs, reusing the existing read serializers and Pundit scopes:

- `resources/list` and `resources/templates/list` — list a bounded set of resources
  (e.g. the user's recent posts/notes per org) and the URI templates for addressing
  any entity (`campsite://{org_slug}/posts/{public_id}`, `…/notes/{public_id}`,
  `…/threads/{public_id}`).
- `resources/read` — resolve a `campsite://` URI to its serialized content under the
  same Pundit policy as the equivalent read tool; unknown/forbidden URIs return the
  standard not-found/authorization error.
- **Subscriptions** (`resources/subscribe` / `notifications/resources/updated`) are
  specified but gated behind a transport-capability spike (see `design.md`,
  Decision B3) and MAY be deferred again if the remote Streamable-HTTP transport
  cannot hold a server→client stream under Hatchbox/nginx.

### C. MCP prompts

Advertise the `prompts` capability and ship a small catalog of Campsite workflow
templates via `prompts/list` / `prompts/get`, each returning messages that drive the
existing tools:

- `triage_inbox` — walk `list_notifications`, summarize, propose follow-ups.
- `draft_standup` — summarize the user's recent posts/comments into a status update.
- `summarize_thread` — condense a post (with comments) or message thread.

Prompts take typed `arguments` (e.g. `org_slug`, time window) and perform no
mutation themselves.

## Capabilities

### Modified Capabilities
- `mcp-tools`: adds the attachment tool set (`create_upload`, `attach_file`,
  `upload_attachment`) to the catalog. `create_upload` gates on `mcp` only (mints
  credentials, writes nothing); `attach_file`/`upload_attachment` require the write
  scope matching the subject (`write_post`/`write_note`/`write_message`).

### Added Capabilities
- `mcp-resources`: the server advertises the `resources` capability and exposes
  Campsite entities as `campsite://` URIs (list, templates, read), authorized by the
  same Pundit policies as the read tools. Change subscriptions are specified but
  conditional on transport support.
- `mcp-prompts`: the server advertises the `prompts` capability and exposes a
  catalog of Campsite workflow templates (list, get) that orchestrate existing tools
  and perform no mutation.

## Impact

- **New code**: three `McpTool` subclasses for attachments; an `McpResource`
  layer (URI parsing + serializer dispatch) wired into `McpServer.build` via the
  gem's `resources` / `resources_read_handler` (and `resources_subscribe_handler`
  if the spike passes); an `McpPrompt` catalog wired via `prompts`. `McpServer.build`
  gains `resources:`, `prompts:`, and a `capabilities:` hash. Tests in
  `test/controllers/mcp_controller_test.rb`.
- **Reused, unchanged contracts**: `PresignedPostFields` / `generate_*_presigned_post_fields`,
  `Attachment.create!` and the per-subject `attachments` associations, the subject
  `:update?` / `:create_attachments?` policies, and the `AttachmentSerializer` /
  `PostSerializer` / `NoteSerializer` / `MessageThreadSerializer` read serializers.
  No policy is bypassed; resources and the `upload_attachment` path run the same
  authorization as the equivalent tool.
- **No new OAuth scope** — attachments reuse `write_post`/`write_note`/`write_message`;
  resources reuse the read scopes; prompts require `mcp` only.
- **Deliberately excluded**: any attachment delete/reorder tool; Figma/remote-node
  attachment variants; resource subscriptions if the transport spike fails; and any
  prompt that performs a mutation without an explicit tool call.
- **Known blocker carried forward**: note **body** editing (`append_to_note`)
  remains blocked on generating a valid collaborative `description_state` for a note
  and is scoped here only as a spike (tasks 5.x), not a deliverable.
- **Out of scope**: any LLM/inference, and the staging end-to-end verification of the
  base server (`add-mcp-server` tasks 6.2/6.3), which is tracked separately.
