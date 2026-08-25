# Campsite MCP Server

Campsite exposes a **remote [MCP](https://modelcontextprotocol.io) server** mounted
inside this Rails API. It lets people connect Campsite from an LLM client (Claude,
etc.) the same way they connect Notion or PostHog — pick "Campsite", sign in, and
grant access. The server runs **no model inference**; it only exposes tools that run
against existing Campsite domain logic under the connected user's permissions.

## Connecting from Claude (or any MCP client)

Add a custom connector pointing at:

```
https://<api-host>/mcp
```

This must be the **API host**, which is distinct from the web host. The web app
(Next.js/Vercel) routes `/<something>` as an organization slug, so pointing a client
at `https://<web-host>/mcp` does **not** reach Rails — it 307-redirects to
`/mcp/posts` and the `/.well-known/*` discovery paths 404. Always use the separate
API subdomain.

Examples:

- Campsite.com prod: `https://api.campsite.com/mcp`
- Homelab deployment: use the API hostname configured for the deployment (the
  web hostname remains a separate Next.js service and must not be used)
- Locally: `http://api.campsite.test:3001/mcp`

The client then performs the standard remote-MCP OAuth dance automatically — no
admin needs to hand-provision credentials:

1. The client fetches `/.well-known/oauth-protected-resource` (RFC 9728) to learn
   which authorization server protects `/mcp`. An unauthenticated request to `/mcp`
   also returns `401` with a `WWW-Authenticate: Bearer resource_metadata="…"` header
   pointing at the same metadata.
2. It fetches `/.well-known/oauth-authorization-server` (RFC 8414) for the
   authorize/token/registration endpoints, supported scopes, and PKCE support.
3. When `client_id_metadata_document_supported` is advertised, the client uses
   its HTTPS Client ID Metadata Document (CIMD) URL as `client_id`. Campsite
   fetches and validates that document. Older clients can still **dynamically
   register** via `POST /oauth/register` (RFC 7591), receiving a `client_id` and,
   for confidential clients, a `client_secret`.
4. It runs Doorkeeper's authorization-code + S256 PKCE flow. The user signs in and sees a
   Campsite consent screen, then approval issues an `mcp`-scoped access token.

🟡 CIMD is implemented but disabled until an operator creates and globally enables
the `mcp_cimd_registration` Flipper feature. While disabled, discovery does not
advertise CIMD or RFC 9207 support and clients continue to use pre-registration or
DCR. When enabled, authorization responses include RFC 9207 `iss`, exactly matching
the discovery document's `issuer`.

All of this is served same-origin **on the API host** (`/mcp`, the `/.well-known/*`
discovery paths, and `/oauth/*` all live on `<api-host>`) and backed by Campsite's
existing Doorkeeper OAuth2 provider. It is not served from the web host.

## Scopes

The connection is gated by the **`mcp`** scope. Individual tools require additional
scopes:

| Scope                                               | Grants                                                                                                                 |
| --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `mcp`                                               | Access to the `/mcp` endpoint at all (required).                                                                       |
| `read_*`                                            | Read tools (organizations, members, projects, posts, notes, messages).                                                 |
| `write_post`                                        | `create_post`, `add_comment`, `add_reaction`, `resolve_post`, `update_post`, `reply_to_comment`.                       |
| `write_message`                                     | `send_message`, `create_message_thread`.                                                                               |
| `write_note`                                        | `create_note`, `update_note`.                                                                                          |
| `write_project`                                     | `create_project`.                                                                                                      |
| `attach_file` / `upload_attachment` / `speak_reply` | gated by the subject's write scope (`write_post` for posts, `write_note` for notes); `create_upload` needs only `mcp`. |

The access token is **user-scoped**, so one connection works across _every_
organization the user belongs to. Tools act as the user (the same authorization as
the `/api/v1` REST API), never as the connector application.

## Tools

Every tool runs through the same Pundit policies and Blueprinter serializers as the
REST API, so a user can never see or do anything via MCP they couldn't do via the
API. Most tools take an `org_slug` argument — call `list_organizations` first to
discover the organizations and slugs available.

### Read tools

| Tool                        | Description                                                                                                                  |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `list_organizations`        | Organizations the user belongs to, with their slugs.                                                                         |
| `list_members`              | Members of an org, with ids/usernames (for @mentions and DMs).                                                               |
| `list_projects`             | Projects (channels) in an organization.                                                                                      |
| `list_posts`                | Published posts, optionally filtered to one project.                                                                         |
| `search_posts`              | Full-text search over an org's posts.                                                                                        |
| `read_post`                 | A single post and its top-level comments.                                                                                    |
| `list_message_threads`      | The user's DMs and group chats in an organization.                                                                           |
| `read_messages`             | Recent messages in a thread.                                                                                                 |
| `list_notes`                | Notes in an organization the user can see.                                                                                   |
| `read_note`                 | A single note with its content.                                                                                              |
| `whoami`                    | The connected user's identity and their member id in each org.                                                               |
| `list_notifications`        | The user's inbox (or activity) notifications in an org.                                                                      |
| `mark_notification_read`    | Mark one of the user's own notifications as read (mutates self only; no extra scope).                                        |
| `create_follow_up`          | Set a personal follow-up reminder on a post, note, or comment for yourself (mutates self only; no extra scope beyond `mcp`). |
| `get_attachment_transcript` | Get transcription status and plain text for an attachment the caller can view.                                               |

### Write tools (additive only)

| Tool                    | Description                                                                                          | Scope                       |
| ----------------------- | ---------------------------------------------------------------------------------------------------- | --------------------------- |
| `create_post`           | Create a post in an org / project.                                                                   | `write_post`                |
| `add_comment`           | Comment on a post or a note.                                                                         | `write_post`                |
| `add_reaction`          | Add an emoji reaction to a post or comment.                                                          | `write_post`                |
| `resolve_post`          | Resolve or unresolve a post (optional resolution note).                                              | `write_post`                |
| `update_post`           | Update a post's title, body, or project.                                                             | `write_post`                |
| `reply_to_comment`      | Reply to an existing comment (threaded reply).                                                       | `write_post`                |
| `create_project`        | Create a new project (channel) in an org.                                                            | `write_project`             |
| `send_message`          | Send a message into an existing thread.                                                              | `write_message`             |
| `create_message_thread` | Start a new DM or group chat.                                                                        | `write_message`             |
| `create_note`           | Create a note (optionally in a project), body set at creation.                                       | `write_note`                |
| `update_note`           | Update an existing note's **title** only.                                                            | `write_note`                |
| `create_upload`         | Get presigned S3 fields to upload a file (mints credentials only, no Campsite write).                | `mcp`                       |
| `attach_file`           | Attach an already-uploaded file (by S3 key) to a post or note.                                       | `write_post` / `write_note` |
| `upload_attachment`     | Upload a small file inline (base64, ≤5 MB) and attach it to a post or note.                          | `write_post` / `write_note` |
| `speak_reply`           | Synthesize an MP3 and attach it to a post or note; accepts an optional provider-specific `voice_id`. | `write_post` / `write_note` |

> **Attaching files.** Two paths: for any file, `create_upload` → upload the bytes to
> the returned S3 `url` → `attach_file` with the returned `key` as `file_path`. For
> small files (≤5 MB), `upload_attachment` does it in one call with inline base64.
> Both attach to a **post or note**; the write scope follows the subject. Attaching to
> comments or messages is set at creation time in the REST API and is not exposed here.

> **Voice attachments.** Attachment payloads include nullable `transcript` and
> `transcription_job_status` fields. Audio attachments are processed asynchronously;
> poll `get_attachment_transcript` when the status is `pending`. `speak_reply`
> defaults to the connected user's nullable `voice_id` (also returned by `whoami`)
> when no override is supplied. The default Edge provider requires outbound HTTPS;
> ElevenLabs is optional and falls back to Edge if its credentials or request fail.

> **Note bodies are write-once.** A note's body (`description_html`) can only be
> set at `create_note` time. Editing an existing note's body is **unsupported** —
> the body is collaborative (real-time) state, so `update_note` only changes the
> title. To put fresh content in a note, create a new note per run rather than
> trying to rewrite an existing one's body.

There are **no delete or bulk-destructive tools** — the connector is safe by
default.

### @mentioning people

`create_post`, `add_comment`, and `send_message` accept a mention **shorthand** in
their HTML body: write `<@member_public_id>` and the server expands it into
Campsite's mention markup (the member is notified). Get member ids from
`list_members`. Example: `"<p>cc <@bnpw503z2pda> please review</p>"`.

## Prompts

The server also advertises **prompts** — reusable, server-authored workflow
templates a user picks from their MCP client (in Claude, the "/" prompt menu). A
prompt performs **no writes and no inference**: it returns instruction messages that
drive the tools above, so it needs only the `mcp` scope. Each takes a required
`org_slug` argument (plus optional ones).

| Prompt             | Arguments                            | What it does                                                                                 |
| ------------------ | ------------------------------------ | -------------------------------------------------------------------------------------------- |
| `triage_inbox`     | `org_slug`, `filter?`                | Walk `list_notifications`, summarize what needs attention, propose `create_follow_up`s.      |
| `draft_standup`    | `org_slug`, `since?`                 | Summarize your recent posts/comments into a Done / In progress / Blocked update.             |
| `summarize_thread` | `org_slug`, `post_id?`, `thread_id?` | Condense a post (with comments) or a message thread into TL;DR + decisions + open questions. |

## Resources

The server also exposes Campsite entities as MCP **resources** — addressable,
readable `campsite://` URIs a client can browse and attach as context, separate from
the tool-call loop. A resource read returns the same data (and runs the same Pundit
policy and read scope) as the equivalent `read_*` tool, so resources add
addressability, never new access.

URI scheme:

```
campsite://{org_slug}/posts/{public_id}
campsite://{org_slug}/notes/{public_id}
campsite://{org_slug}/threads/{public_id}
```

- `resources/templates/list` advertises these templates — use them to address any
  entity directly.
- `resources/list` returns a bounded set of your recent posts and notes across the
  orgs you belong to (for discovery). Threads are addressable by template but are not
  enumerated.
- `resources/read` resolves a URI to its serialized content; an unknown URI,
  forbidden entity, or org you don't belong to returns a JSON-RPC error.

Resource change **subscriptions** (`resources/subscribe`) are not advertised yet —
they need a server→client stream the remote transport hasn't been shown to hold; see
the subscription spike in the `add-mcp-tier-3` change.

## Operating notes

- **Rollout kill-switch:** the endpoint is enabled by default. To disable it (e.g.
  for a gradual rollout or incident), register and turn off the Flipper feature
  `mcp_server` (globally, or per-user). When the feature is unregistered, `/mcp` is
  on.
- **CIMD rollout:** `mcp_cimd_registration` is a separate global Flipper feature
  and is off when unregistered. Enable it only after the focused OAuth tests pass.
  The feature gates URL-client resolution and the two discovery indicators
  (`client_id_metadata_document_supported` and
  `authorization_response_iss_parameter_supported`) together. Roll back by
  disabling this feature first; existing DCR and manually registered clients are
  unaffected.
- **CIMD fetch/cache policy:** client IDs must be public HTTPS hostnames with a
  non-root path and no userinfo, query, fragment, IP literal, or dot segment.
  Campsite resolves the hostname once, rejects the entire result if any address is
  special-use, pins one accepted address for the verified TLS connection, follows
  no redirects, and reads at most 5 KiB. Only valid JSON documents are cached in
  `Rails.cache`: explicit `no-store`, `no-cache`, or `private` responses are not
  cached; positive freshness is clamped to 1 minute through 1 hour; absent
  freshness defaults to 5 minutes. Expired metadata is never used after a failed
  refresh. Logs contain only outcome categories and hostnames, never document
  bodies, authorization codes, tokens, secrets, or full client-ID URLs.
- **Abuse control:** dynamic client registration (`POST /oauth/register`) is open
  (so the connector flow needs no manual provisioning) but rate-limited per IP via
  Rack::Attack, and it grants no access on its own — a human still signs in and
  consents before any token is issued.
- **DCR compatibility boundary:** DCR remains supported and advertised through at
  least 2027-07-28. Removal after that date requires usage evidence, a migration
  plan, a separate OpenSpec change, and release communication.
- **Routing:** `/mcp`, the `/.well-known/*` discovery paths, and `/oauth/*` are
  served by Rails on the **API host** (e.g. `camp-api.polo-apps.com`). They must be
  proxied straight through to Rails by that host's web server (Hatchbox/nginx) and
  not shadowed. Do **not** expect them on the web host: the Next.js web app
  (`camp.polo-apps.com`) treats `/mcp` as an org slug and will 307-redirect it to
  `/mcp/posts`, so clients must point at the API host, never the web host.

## Implementation

- Endpoint: `app/controllers/mcp_controller.rb` (auth + dispatch via the `mcp` gem).
- Discovery: `app/controllers/well_known_controller.rb`,
  `app/controllers/concerns/mcp_discoverable.rb`.
- Client registration: `lib/oauth/cimd/` and `app/models/oauth_application.rb`
  (CIMD); `app/controllers/oauth/registrations_controller.rb` (DCR fallback).
- Tool layer: `app/mcp/` (`McpServer`, `McpTool`, `McpToolRegistry`,
  `McpRequestContext`, and `McpTools::*`).
- Prompt layer: `app/mcp/` (`McpPrompt`, `McpPromptRegistry`, and `McpPrompts::*`).
- Resource layer: `app/mcp/` (`McpResource`, `CampsiteMcpServer` for the lazy
  resources list, and the shared `McpOrganizationResolver`).
