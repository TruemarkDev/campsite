Ordered by ascending risk: prompts (C) → resources (B) → attachments (A) →
subscriptions spike. Each top-level phase is independently shippable and MAY be split
into its own change.

## 1. Server wiring

- [x] 1.1 Extend `McpServer.build` to pass `prompts:`, `resource_templates:`, and an
      explicit `capabilities:` hash (`tools`, `prompts.listChanged`,
      `resources.listChanged`); the resources list is computed lazily via
      `CampsiteMcpServer` (a thin `MCP::Server` subclass) so it does not query on every
      tools/call; the per-request server keeps handlers under the authenticated context
- [x] 1.2 Confirm the `initialize` handshake now advertises both `prompts` and
      `resources` capabilities (extended the handshake tests in `mcp_controller_test.rb`;
      asserted `resources.subscribe` is NOT advertised yet)

## 2. MCP prompts (Phase C — ship first)

- [x] 2.1 Add an `McpPrompt` base + `McpPromptRegistry` catalog with typed
      `arguments`; no mutation in any prompt handler
- [x] 2.2 `triage_inbox` — template that drives `list_notifications` →
      summarize → propose `create_follow_up`
- [x] 2.3 `draft_standup` — template that summarizes the user's recent posts/comments
      into a status update (args: `org_slug`, time window)
- [x] 2.4 `summarize_thread` — template for a post (with comments) or message thread
- [x] 2.5 Register prompts in `McpServer.build`; update `docs/mcp_server.md` with a
      Prompts section
- [x] 2.6 Tests: `prompts/list` returns the catalog; `prompts/get` returns messages
      for each; a guard test asserts every tool name referenced by a prompt exists in
      `McpToolRegistry`

## 3. MCP resources (Phase B)

- [x] 3.1 Add an `McpResource` URI layer: parse `campsite://{org_slug}/{type}/{public_id}`,
      resolve org membership + 2FA via the shared `McpOrganizationResolver` (extracted
      from `McpTool#organization_context!` so the gate can't drift), load under
      `policy_scope`, render the existing serializer
- [x] 3.2 `resources/templates/list` — advertise URI templates for `posts`, `notes`,
      `threads`
- [x] 3.3 `resources/list` — bounded list of the user's recent posts/notes per org
      (capped per type per org; threads addressable by template but not enumerated;
      2FA-blocked orgs skipped)
- [x] 3.4 Register `resources_read_handler` resolving the URI under the authenticated
      context; unknown URI → error, forbidden record → authorization error, thread URIs
      pinned to the slug's org; gated by the read scope for that type
- [x] 3.5 Update `docs/mcp_server.md` with a Resources section and the URI scheme
- [x] 3.6 Tests: list, templates/list, read (per type), unknown-URI error,
      Pundit-denial read, cross-org isolation, thread-org pinning

## 4. Resource subscriptions (Phase B — spike-gated, MAY defer)

- [x] 4.1 **Spike**: documented in `spike-subscriptions.md`. Outcome: **does not
      pass** — blocked at the architecture level (stateless per-request mounting + GET
      rejected; gem keeps SSE sessions in process memory with no Redis/pubsub backplane;
      multi-worker Puma makes in-process delivery undeliverable; no change-event bridge).
      nginx buffering is the only staging-only unknown and is moot until the rest is built.
- [ ] 4.2 ~~If the spike passes~~ — not pursued (spike did not pass)
- [ ] 4.3 ~~If the spike passes~~ — not pursued (spike did not pass)
- [x] 4.4 Spike did not pass → `resources.subscribe` is NOT advertised (see
      `McpServer.build` capabilities) and resources ship without subscriptions; re-defer
      noted in `docs/mcp_server.md` and `spike-subscriptions.md` (rework checklist + the
      staging probe to run if revisited)

## 5. Attachments (Phase A)

- [x] 5.1 `create_upload` (org-scoped, `mcp` only) — wraps
      `organization.generate_post_presigned_post_fields(mime_type)`, returns the presigned
      fields + object `key` via `PresignedPostFieldsSerializer`
- [x] 5.2 `attach_file` (org-scoped, requires subject write scope) — creates an
      `Attachment` from `file_path` + `file_type` and links it to a `post`/`note` subject
      via its `attachments` association, authorizing the subject `:update?`. **Scoped to
      post + note** (the subjects with a standalone REST attachment-create endpoint);
      comment/message attachments are set at creation time in REST, so they are out of
      scope (noted in `docs/mcp_server.md`). Subject resolution + scope live in the shared
      `McpTools::ResolvesAttachmentSubject`.
- [x] 5.3 `upload_attachment` (org-scoped, requires subject write scope) — accepts
      inline base64 `content` + `file_type`, enforces `MAX_INLINE_UPLOAD_BYTES` (5 MB;
      rejects larger with a `ToolError` pointing at `create_upload`/`attach_file`), uploads
      server-side via `S3_BUCKET.object(key).put`, creates+links in one call
- [x] 5.4 Confirmed NO attachment delete/reorder tool and no Figma/remote-node variant
      is registered (the tool input schema exposes only the safe param subset)
- [x] 5.5 Registered the three tools in `McpToolRegistry` (`create_upload` grouped with
      reads as `mcp`-only; `attach_file`/`upload_attachment` as writes); updated
      `docs/mcp_server.md` (tools + scope table)
- [x] 5.6 Tests: `create_upload` returns presigned fields; `attach_file` links to post
      and note; `upload_attachment` round-trips a small file (stubbed S3) and rejects an
      over-cap file; each blocked without the subject's write scope; Pundit-denial path;
      unknown subject_type rejected

## 6. Deferred spike — note body editing (carried forward, NOT a deliverable)

- [ ] 6.1 Spike whether a valid collaborative `description_state` can be generated for
      a note body edit / `append_to_note`; if yes, file a follow-up change; if no,
      document why it stays deferred

## 7. Gates

- [x] 7.1 `bundle exec rubocop app/mcp/ test/...` clean and
      `bin/rails test test/controllers/mcp_controller_test.rb` green (92 runs, 0 failures)
      across Phases C + B + A
