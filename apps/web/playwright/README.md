# Browser acceptance tests

From the repository root, run:

```sh
pnpm test:browser
```

Use the pinned mise toolchain (`mise exec -- pnpm test:browser` also selects it
explicitly), installed workspace and API gems/asset dependencies, native
PostgreSQL with permission to create/drop databases, and native Redis. No local
Docker or existing application/browser login is required. Install the matching
headless browser once with `pnpm -F @campsite/web exec playwright install chromium`.
The existing API setup installs its separate asset lockfile; when provisioning
a fresh checkout, run `pnpm --dir api install --frozen-lockfile` as well.
The hostnames `app.campsite.test`, `api.campsite.test` and `auth.campsite.test`
must resolve only to loopback. Ports 3100, 3101, 3102 and 9100 must be free.

The runner creates a random `campsite_browser_<id>` database and two synthetic
users with a fresh password. It starts Rails in test mode, styled-text, sync and
Next through Playwright's native web-server lifecycle. Rails jobs are fake,
mail delivery uses the test adapter, and WebMock blocks non-local requests.
Browser HTTP/WebSocket requests are restricted to fixture hosts. Only the AI
provider response is mocked; note synchronization and persistence use the real
local services. Authentication uses the real sign-in form; fixture session state
is shared in memory; no reusable storage-state file is created. Failed request
diagnostics can contain synthetic fixture session headers.

The eight Chromium cases cover dashboard loading, post creation/deletion, existing
poll editing/voting/reload, AI proposal propagation/rejection across two clients,
note collaboration/canonical API persistence/reload, and an independent member's
private-document and read-only permission boundaries, connected-viewer revocation,
and disconnected edits followed by reconnect/reload. Revocation checks the native
logical document-close message; a multiplexed physical socket can remain open.
The obsolete skipped poll
creation test was replaced: the current composer no longer offers poll creation.

`PG_TEST_HOST`, `PG_TEST_PORT`, `PG_TEST_USER`, `PG_TEST_PASSWORD` and
`BROWSER_REDIS_URL` can select local test services. Remote database and Redis
hosts are rejected. Redis defaults to database 14; synchronization keys have a
random per-run prefix. Cleanup unlinks only that prefix and drops only the
generated fixture database. Normal exit, test failure, SIGINT and SIGTERM run
cleanup; an uncatchable kill or machine crash can leave resources behind.

Next uses a per-run cache under `playwright/.cache/<id>/next`. The runner restores
its generated `next-env.d.ts` reference and removes per-run logs/artifacts after
cleanup. Set `BROWSER_KEEP_DIAGNOSTICS=1` to retain synthetic fixture diagnostics
locally; do not commit them. Screenshots, video and traces are disabled. Next may
also generate its standard managed agent instruction files during development.

Pass native Playwright arguments after the command, for example:

```sh
pnpm test:browser -- --list
pnpm test:browser -- ai-note-editing.spec.ts
```

`--list` discovers cases without creating a database or starting services. The
suite runs serially with no retries and refuses to reuse unrelated servers.
Child environments allow runtime settings and explicit test configuration only;
unrelated operator credentials are excluded. Native runtime paths take precedence
over shims that could reintroduce deployment variables.
