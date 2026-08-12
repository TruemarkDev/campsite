# Devtools Upgrade Handoff

## Completed commits

- `fad6d82` — `chore: upgrade to ESLint 10, @types/node 24, prettier 3.9, jsdom 30`
- `0fc1e1f` — `chore: upgrade vite to v8 (rolldown) and @vitejs/plugin-react to v6`
- `3805ff1` — `chore(web): switch dev/build to Turbopack`

No commits were pushed, merged, or submitted as a pull request.

## Validation

### Phase 1

- `mise exec -- pnpm install` — passed; lockfile passed the repository supply-chain policy.
- `mise exec -- pnpm lint` — passed: 6/6 tasks, 0 errors, 21 pre-existing warnings.
- `mise exec -- pnpm test` — passed: 9/9 tasks; web 129 tests, editor 80, sync-server 25, styled-text-server 24, config 2.

### Phase 2

- `mise exec -- pnpm install` — passed; lockfile passed the repository supply-chain policy without a new exemption.
- `mise exec -- pnpm test` — passed after the Vite config migration: 9/9 tasks with the same test counts as Phase 1.

### Phase 3

- `mise exec -- pnpm install` — passed; WDYR and the inactive Jotai SWC plugin were removed from the dependency graph.
- `mise exec -- pnpm --filter @campsite/web lint` — passed.
- `mise exec -- pnpm --filter @campsite/web build` — passed with Next.js 16.3.0 Turbopack; compilation, TypeScript, Sentry's `runAfterProductionCompile`, page-data collection, and all 44 static pages completed.
- `mise exec -- pnpm --filter @campsite/web dev --hostname 127.0.0.1` — Turbopack ready in 315 ms.
- `curl http://127.0.0.1:3000/robots.txt` — HTTP 200.
- `curl http://127.0.0.1:3000/` — Turbopack compiled the route, then the application returned HTTP 500 because the expected local API was not running at `127.0.0.1:3001` (`ECONNREFUSED`). The dev server was stopped cleanly.

## Compatibility decisions

- Kept `analyze` on explicit `next build --webpack`; only normal `dev` and `build` use the Next.js 16 default Turbopack bundler.
- Removed the custom webpack hook. `NEXT_PUBLIC_VERCEL_GIT_COMMIT_SHA` is already inlined by Next.js without `DefinePlugin`.
- Removed Why Did You Render and its development entry injection.
- Removed `.swcrc` and `@swc-jotai/react-refresh`: the legacy transform was not present in Turbopack output, while Turbopack provides React Fast Refresh directly.
- Kept `@sentry/nextjs` at 10.70.0 because its Turbopack production hook ran successfully. Local builds intentionally skip release creation and source-map upload when `SENTRY_AUTH_TOKEN` is absent.
- Overrode `universal-github-app-jwt` from 2.2.0 to the upstream 2.2.2 patch, whose explicit `node:crypto` export fixes Turbopack tracing for `/api/latest-release`.

## Warnings and follow-ups

- The successful Turbopack build reports a non-fatal trace warning: `Module not found: Can't resolve 'styled-jsx/style.js'` under `./apps/web/_`. The standalone trace still includes the resolved `styled-jsx/style.js`; investigate Next/styled-jsx graph deduplication separately if warning-free output is required.
- The repository's broader Bead `campsite-x7r` remains open because it also covers `apps/site`; the KICKOFF-requested `apps/web` scope is complete and recorded there.
- Full root-route dev UAT requires the local API on port 3001. The backend-independent `/robots.txt` smoke route passed.
- ESLint 10 still produces upstream peer-manifest warnings in parts of the Next/Sanity plugin stack, although the repository lint gate passes.
