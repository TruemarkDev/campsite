# Spike — `subscriptions/listen` over remote Streamable HTTP (task 4.1)

> **Updated 2026-08-13 for MCP 2026-07-28.** The prior
> `resources/subscribe` / `resources/unsubscribe` plus HTTP GET/SSE design was
> removed from MCP. Do not implement those RPCs, a companion GET endpoint,
> `Last-Event-ID`, or SSE replay from the older version of this spike. Any such
> language remaining in the surrounding Tier 3 proposal/spec/tasks describes the
> superseded pre-2026-07-28 model; this update is the outcome of the task 4.1
> spike.

**Question:** can Campsite's remote Streamable-HTTP path hold the new single
long-lived server→client POST response through Rails/Puma and Hatchbox/nginx,
while delivering changes raised in other web or Sidekiq processes?

**Method:** read the MCP 2026-07-28 subscriptions and transport changes, then
re-evaluate the current `/mcp` controller, pinned `mcp` 0.22.0 gem, clustered
Puma deployment, and Campsite change-event sources. The network-level proxy
behavior still needs a staging probe if the application-level blockers are ever
addressed.

## The 2026-07-28 model

`subscriptions/listen` is one long-lived JSON-RPC request sent by HTTP POST. Its
`notifications` filter opts in independently to:

- `toolsListChanged`
- `promptsListChanged`
- `resourcesListChanged`
- `resourceSubscriptions` (an array of resource URIs)

The server's first stream message must be
`notifications/subscriptions/acknowledged`, containing the subset it accepts.
The acknowledgment and every later notification carry
`io.modelcontextprotocol/subscriptionId`; the value is the JSON-RPC request ID
of the `subscriptions/listen` request. The server must not send types the client
did not request.

For HTTP, the client cancels by closing the response stream. A server ending it
gracefully should send the empty response to the original request before
closing. There is no resumability or redelivery: `Last-Event-ID` and SSE event
IDs are gone. If the stream breaks, the request is lost and the client reissues
`subscriptions/listen` as a new request with a new request ID.

## Findings

### F1 — The removed GET/session API is no longer the blocker

The old spike treated `McpController` rejecting GET as decisive because the
prior transport opened a separate GET SSE channel and attached
`resources/subscribe` state to a session. MCP 2026-07-28 removes that design.
The current GET rejection is therefore irrelevant to a conforming
`subscriptions/listen` implementation, and a future implementation does not
need `Mcp-Session-Id`, a GET-side session map, an unsubscribe RPC, an event
store, or `Last-Event-ID` replay merely to support subscriptions.

This is a real simplification: the filter, stream lifetime, cancellation, and
correlation all belong to one POST request.

### F2 — The current Rails controller still cannot hold a POST response open

`McpController#handle` builds a fresh `McpServer`, synchronously calls
`server.handle_json(request.raw_post)`, and immediately renders the returned
JSON:

```ruby
context = McpRequestContext.new(token: doorkeeper_token)
server = McpServer.build(context: context)
response_json = server.handle_json(request.raw_post)
render(json: response_json)
```

There is no streaming response body, request-lifetime writer, disconnect/cancel
handling, or way for later application events to write another frame to that
response. A `subscriptions/listen` request would need a transport that keeps the
POST response open, sends the acknowledgment first, retains the accepted filter
for that request, and serializes later notifications onto that same response.
Per-request server construction is not inherently forbidden by the new model,
but it must live for the response lifetime rather than return one JSON value.

### F3 — The pinned Ruby SDK implements the removed protocol, not the new method

`api/Gemfile.lock` pins `mcp` 0.22.0. Its method table and handlers contain
`resources/subscribe` / `resources/unsubscribe`, and its
`StreamableHTTPTransport` implements the old in-memory session plus GET-SSE
shape. It has no `subscriptions/listen` method or acknowledgment/filter support.

Therefore mounting the gem's existing transport would implement the API MCP
2026-07-28 removed. Campsite needs an SDK release that explicitly supports the
2026-07-28 protocol (verified at implementation time) or a reviewed transport
implementation; the 0.22.0 subscription code must not be reused as if it were
compatible.

### F4 — Cross-process delivery remains a hard blocker

The new stream is request-scoped, but it still lives in one Puma worker process.
`config/puma.rb` defaults to two clustered workers, and the entity change that
should produce `notifications/resources/updated` can originate in another web
worker or Sidekiq process. Process memory is not shared.

The stream-owning worker needs a cross-process fan-out source (for example, a
bounded Redis pub/sub channel) so it can receive relevant changes and apply that
request's acknowledged filter. The new protocol removes the need for a durable
SSE replay store, but it does **not** make events raised in another process
magically reach the held response.

### F5 — A long-lived POST still consumes server capacity

Puma defaults to five threads per worker. A conventionally held streaming
response can occupy a worker thread or other finite connection resource for its
entire lifetime. Enough listeners can exhaust `workers × threads`, database/web
capacity, reverse-proxy connections, or file descriptors and starve ordinary
API traffic.

Before enabling subscriptions, Campsite needs explicit concurrency limits,
idle/maximum lifetime policy, disconnect cleanup, and either an isolated
streaming service/pool or measured proof that the Rails/Puma deployment can
carry the expected listener count safely.

### F6 — Hatchbox/nginx streaming behavior is still unknown

Although the stream now begins with POST instead of GET, nginx can still buffer
the response or terminate it on read/idle timeouts. The `/mcp` path needs a
configuration that flushes each event promptly, does not cache/buffer the
stream, and keeps it open for the supported lifetime. Whether Hatchbox's managed
nginx permits the required per-location behavior is not determinable from this
repository.

This remains a staging-only question, but it is not worth probing until F2–F5
have an implementation suitable for staging.

### F7 — Campsite still has no MCP subscription event bridge

Resource subscriptions only become useful if a post/note/thread mutation
produces the corresponding `notifications/resources/updated` for the exact
`campsite://` URI. Campsite already emits realtime invalidations through Pusher
and `*_stale` signals, but nothing bridges those signals to an MCP
subscription filter. List-change notifications likewise need explicit tool,
prompt, or resource catalog change sources.

The bridge must publish a bounded, authorization-safe event identity. The
stream worker must re-check enough context to avoid leaking the existence of a
resource that the connected user can no longer access.

## Does the new model change the recommendation?

It improves the design in meaningful ways:

- one POST owns the filter, acknowledgment, notifications, and cancellation;
- there is no separate GET stream or session-affinity requirement;
- there is no unsubscribe RPC or replay/event-ID store; and
- reconnect behavior is honest and simple: issue a new request.

Those changes reduce protocol and state-management work. They do not solve the
current controller's lack of a streaming response, the pinned SDK's protocol
mismatch, cross-process event delivery, Puma/proxy capacity, or missing domain
event bridge. The value is also still incremental: clients can poll
`resources/read` and the list methods without holding scarce server capacity.

## Verdict

**Defer subscriptions by default.** The 2026-07-28 model is cleaner than the
removed API, but Campsite is still blocked at the application and deployment
architecture levels. Continue serving list/read resources without advertising
or implementing subscription support. In particular, do not add
`resources/subscribe`, `resources/unsubscribe`, a GET SSE endpoint, or
`Last-Event-ID` handling.

Revisit only when there is a concrete client/user need that justifies an SDK or
transport upgrade, a cross-process event path, and reserved streaming capacity.

## If pursued later — required rework and staging probe

1. Select and pin an MCP SDK/transport that explicitly implements protocol
   2026-07-28 `subscriptions/listen`, including filters, acknowledgment ordering,
   subscription IDs, cancellation, and graceful closure. Do not adapt the
   0.22.0 `resources/subscribe` handlers.
2. Replace the synchronous one-JSON controller path for this method with an
   authenticated long-lived POST response that remains tied to its
   `McpRequestContext`, writes the acknowledgment first, and cleans up promptly
   on disconnect.
3. Add a bounded cross-process fan-out path so changes from any Rails/Sidekiq
   process reach the worker holding each applicable stream; retain only the
   request's accepted filter and ephemeral delivery state.
4. Bridge authorized Campsite change signals to the corresponding resource and
   list-change notifications, including permission-change behavior.
5. Establish listener limits, maximum/idle lifetimes, backpressure, slow-client
   handling, deploy/shutdown draining, observability, and a capacity-isolation
   strategy for long-lived responses.
6. Configure Hatchbox/nginx to flush without buffering or caching and to preserve
   the supported response lifetime.
7. **Staging probe:** POST a real `subscriptions/listen` request (with the
   2026-07-28 protocol metadata, valid bearer token, required MCP HTTP headers,
   and `Accept: text/event-stream`), then verify:
   - `notifications/subscriptions/acknowledged` is the first message and reports
     only the accepted filter;
   - a mutation from a different web/Sidekiq process produces the authorized
     notification with the same `io.modelcontextprotocol/subscriptionId`;
   - frames arrive promptly and the stream survives beyond proxy timeouts;
   - client close releases all server resources; and
   - after a forced disconnect, no replay is attempted and a fresh request with
     a new request ID establishes a new subscription.
