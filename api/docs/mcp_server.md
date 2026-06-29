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

(e.g. `https://api.campsite.com/mcp`; locally `http://api.campsite.test:3001/mcp`.)

The client then performs the standard remote-MCP OAuth dance automatically — no
admin needs to hand-provision credentials:

1. The client fetches `/.well-known/oauth-protected-resource` (RFC 9728) to learn
   which authorization server protects `/mcp`. An unauthenticated request to `/mcp`
   also returns `401` with a `WWW-Authenticate: Bearer resource_metadata="…"` header
   pointing at the same metadata.
2. It fetches `/.well-known/oauth-authorization-server` (RFC 8414) for the
   authorize/token/registration endpoints, supported scopes, and PKCE support.
3. It **dynamically registers** itself via `POST /oauth/register` (RFC 7591),
   receiving a `client_id` (and `client_secret` for confidential clients).
4. It runs Doorkeeper's authorization-code + PKCE flow. The user signs in and sees a
   Campsite consent screen, then approval issues an `mcp`-scoped access token.

All of this is served same-origin on the API host and backed by Campsite's existing
Doorkeeper OAuth2 provider.

## Scopes

The connection is gated by the **`mcp`** scope. Individual tools require additional
scopes:

| Scope             | Grants                                                        |
| ----------------- | ------------------------------------------------------------- |
| `mcp`             | Access to the `/mcp` endpoint at all (required).              |
| `read_*`          | Read tools (organizations, members, projects, posts, notes, messages). |
| `write_post`      | `create_post`, `add_comment`, `add_reaction`, `resolve_post`, `update_post`, `reply_to_comment`. |
| `write_message`   | `send_message`, `create_message_thread`.                      |
| `write_note`      | `create_note`, `update_note`.                                 |
| `write_project`   | `create_project`.                                             |

The access token is **user-scoped**, so one connection works across *every*
organization the user belongs to. Tools act as the user (the same authorization as
the `/api/v1` REST API), never as the connector application.

## Tools

Every tool runs through the same Pundit policies and Blueprinter serializers as the
REST API, so a user can never see or do anything via MCP they couldn't do via the
API. Most tools take an `org_slug` argument — call `list_organizations` first to
discover the organizations and slugs available.

### Read tools

| Tool                   | Description                                            |
| ---------------------- | ----------------------------------------------------- |
| `list_organizations`   | Organizations the user belongs to, with their slugs.  |
| `list_members`         | Members of an org, with ids/usernames (for @mentions and DMs). |
| `list_projects`        | Projects (channels) in an organization.               |
| `list_posts`           | Published posts, optionally filtered to one project.  |
| `search_posts`         | Full-text search over an org's posts.                 |
| `read_post`            | A single post and its top-level comments.             |
| `list_message_threads` | The user's DMs and group chats in an organization.    |
| `read_messages`        | Recent messages in a thread.                          |
| `list_notes`           | Notes in an organization the user can see.            |
| `read_note`            | A single note with its content.                       |
| `whoami`               | The connected user's identity and their member id in each org. |
| `list_notifications`   | The user's inbox (or activity) notifications in an org. |
| `mark_notification_read` | Mark one of the user's own notifications as read (mutates self only; no extra scope). |
| `create_follow_up`     | Set a personal follow-up reminder on a post, note, or comment for yourself (mutates self only; no extra scope beyond `mcp`). |

### Write tools (additive only)

| Tool                    | Description                                  | Scope           |
| ----------------------- | -------------------------------------------- | --------------- |
| `create_post`           | Create a post in an org / project.           | `write_post`    |
| `add_comment`           | Comment on a post or a note.                 | `write_post`    |
| `add_reaction`          | Add an emoji reaction to a post or comment.  | `write_post`    |
| `resolve_post`          | Resolve or unresolve a post (optional resolution note). | `write_post`    |
| `update_post`           | Update a post's title, body, or project.     | `write_post`    |
| `reply_to_comment`      | Reply to an existing comment (threaded reply). | `write_post`  |
| `create_project`        | Create a new project (channel) in an org.    | `write_project` |
| `send_message`          | Send a message into an existing thread.      | `write_message` |
| `create_message_thread` | Start a new DM or group chat.                | `write_message` |
| `create_note`           | Create a note (optionally in a project), body set at creation. | `write_note` |
| `update_note`           | Update an existing note's **title** only.    | `write_note`    |

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

## Operating notes

- **Rollout kill-switch:** the endpoint is enabled by default. To disable it (e.g.
  for a gradual rollout or incident), register and turn off the Flipper feature
  `mcp_server` (globally, or per-user). When the feature is unregistered, `/mcp` is
  on.
- **Abuse control:** dynamic client registration (`POST /oauth/register`) is open
  (so the connector flow needs no manual provisioning) but rate-limited per IP via
  Rack::Attack, and it grants no access on its own — a human still signs in and
  consents before any token is issued.
- **Routing:** `/mcp` and the `/.well-known/*` discovery paths must be proxied
  through to Rails by the front-end web server (Hatchbox/nginx) and not shadowed.

## Implementation

- Endpoint: `app/controllers/mcp_controller.rb` (auth + dispatch via the `mcp` gem).
- Discovery: `app/controllers/well_known_controller.rb`,
  `app/controllers/concerns/mcp_discoverable.rb`.
- Dynamic client registration: `app/controllers/oauth/registrations_controller.rb`.
- Tool layer: `app/mcp/` (`McpServer`, `McpTool`, `McpToolRegistry`,
  `McpRequestContext`, and `McpTools::*`).
