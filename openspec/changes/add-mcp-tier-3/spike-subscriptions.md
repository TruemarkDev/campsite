# Spike — resource subscriptions over remote Streamable HTTP (task 4.1)

**Question:** can the remote Streamable-HTTP transport hold a server→client stream
end-to-end through Hatchbox/nginx with Doorkeeper bearer auth, so that
`resources/subscribe` + `notifications/resources/updated` work?

**Method:** static analysis of the `mcp` 0.22 gem transport, our `/mcp` mounting, and
the Puma/Hatchbox deployment shape. The network-level question (does Hatchbox's nginx
keep an SSE connection open) is the one piece that still needs a staging probe — but
the code-level findings below already determine the answer for the current
architecture.

## Findings

### F1 — Our `/mcp` mounting is stateless request/response; GET is rejected
`McpController#handle` (`app/controllers/mcp_controller.rb`) builds a **fresh**
`McpServer` per request and calls `server.handle_json(request.raw_post)` with **no
`session:`** argument, and explicitly returns `405` for GET:

```ruby
return head(:method_not_allowed) if request.get?   # GET (SSE stream) is unsupported
...
server.handle_json(request.raw_post)               # no session → no server→client channel
```

The MCP Streamable-HTTP spec carries server-initiated messages (notifications) on a
**GET-opened SSE stream** bound to a session id. We have neither a session nor a GET
stream, so today subscriptions are structurally impossible — not merely unconfigured.

### F2 — The gem's streaming transport keeps sessions + SSE streams in **process memory**
`StreamableHTTPTransport` (gem `server/transports/streamable_http_transport.rb`)
stores state in an in-process hash guarded by a Mutex:

```ruby
@sessions = {}      # session_id => { get_sse_stream:, server_session:, last_active_at: }
@mutex = Mutex.new
```

`send_notification` delivers `resources/updated` by looking up `@sessions[session_id]`
and writing to its in-memory `get_sse_stream`. There is **no pluggable/Redis session
store and no pub/sub backplane** — a code comment confirms resumability/event-store is
unbuilt (`# TODO: Replace with event store + replay when resumability is implemented`).
Using it also means mounting **one long-lived transport instance** as a Rack app, not
the per-request `McpServer.build` we do now.

### F3 — Multi-process Puma breaks in-memory delivery (the hard blocker)
`config/puma.rb` runs clustered: `workers ENV.fetch("WEB_CONCURRENCY") { 2 }` with
`preload_app!`. A client's GET SSE stream lives in the memory of **one** worker
process. A `resources/updated` must be triggered by a change to the underlying entity
— i.e. from a Sidekiq job or a web request in a **different** process. That event
cannot reach the in-memory `@sessions` of the worker holding the SSE stream. With
`WEB_CONCURRENCY > 1` (the prod default), notifications are simply undeliverable
without a cross-process fan-out (Redis pub/sub) that neither the gem nor our app
provides today.

### F4 — A held SSE stream pins a Puma thread
Puma is threaded (`RAILS_MAX_THREADS` → 5 by default). An open SSE connection occupies
one worker thread for its entire lifetime, so N concurrent subscribers consume N of
`workers × threads` slots and starve normal request throughput. Subscriptions at any
scale need a dedicated/isolated server or a much larger, separately-tuned thread
budget.

### F5 — nginx/Hatchbox must be told not to buffer or time out the stream (the staging-only unknown)
SSE through nginx requires, on the `/mcp` location: `proxy_buffering off`,
`proxy_cache off`, `X-Accel-Buffering: no`, and a long/disabled `proxy_read_timeout`
(default 60s would cut the stream). Whether Hatchbox's **managed** nginx allows this
per-location override is the one thing not determinable from this repo and is what a
staging probe would measure. It is moot until F1–F4 are addressed.

### F6 — There is no change-event source wired to resources
Even with transport + backplane, emitting `resources/updated` needs something to fire
when a post/note changes. Campsite already broadcasts realtime invalidations via
Pusher / `*_stale` signals; a subscription feature would have to **bridge** those to
`server_session.notify_resources_updated(uri:)` for each subscribed URI. That bridge
does not exist yet.

## Verdict

**Subscriptions are blocked at the architecture level, not by a config flag.**
Shipping them requires, at minimum: (a) mount a single long-lived
`StreamableHTTPTransport` (stateless:false) instead of per-request `handle_json`;
(b) a Redis-backed cross-process notification fan-out (the gem has none); (c) a
thread/process budget for held SSE streams; (d) a Pusher→`resources/updated` bridge;
and only then (e) the staging nginx buffering/timeout probe (F5).

This is its own multi-week change, disproportionate to the value of *push* updates
when clients can already poll `resources/read`. **Recommendation: take the task 4.4
path — do not advertise `resources.subscribe`, ship resources without subscriptions
(already the case), and re-defer.**

## If pursued later — required rework + the staging probe

1. Mount one persistent `StreamableHTTPTransport(stateless: false)` Rack app at `/mcp`
   (keep Doorkeeper auth in front); stop rebuilding the server per request for the
   streaming path.
2. Add a Redis pub/sub backplane so a notification published by any process reaches
   the worker holding the subscriber's SSE stream (the gem will need a custom
   session/notification store or an external relay).
3. Isolate or expand the thread budget for held SSE connections.
4. Bridge Pusher / `*_stale` invalidations to `notify_resources_updated(uri:)`.
5. **Staging probe (F5):** with the above in a staging deploy, open
   `GET /mcp` with `Accept: text/event-stream` + a valid bearer token and a session
   id, then mutate a subscribed entity and confirm the `notifications/resources/updated`
   frame arrives and the stream stays open past nginx's read timeout. If nginx buffers
   or cuts it, request the `proxy_buffering off` / `proxy_read_timeout` override from
   Hatchbox for the `/mcp` location.
