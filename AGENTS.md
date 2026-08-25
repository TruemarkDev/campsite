# Project instructions for AI agents

Canonical project context for ALL harnesses (Claude Code, Codex, opencode).
`CLAUDE.md` is just an `@AGENTS.md` import — edit THIS file.

**Stewardship mode** (see `MAINTENANCE.md`): no new features or dependencies;
agents may only merge patch/minor security bumps with CI green. Change
proposals live in `openspec/changes/`.

## Build & Test

Toolchain: node 24.19.0 + ruby 4.0.6 + pnpm 11.9.0 via mise (`mise.toml`).
`.nvmrc`, `api/mise.toml`, every `Dockerfile`, and `package.json` `engines`
all agree on node 24.19.0, the baseline `MAINTENANCE.md` declares.
⚠️ `api/fly.toml` still carries node 26.4.0 in `[build.args]`, but the Fly
deploy is dead (see `api/CLAUDE.md`) — it is not a mirror target.

```bash
# First-time setup
script/setup            # brew deps, api setup, elasticsearch container, pnpm install
pnpm dev:setup          # api db:setup/db:migrate via mise

# Dev servers (overmind, all procs in Procfile)
script/dev              # everything; `overmind connect <proc>` for logs
pnpm dev:core           # just api-dev + web + styled-text-server + sync-server
# Ports: rails api 3001, web 3000, styled-text 3002, site 3003, sync 9000,
#        html-to-image 9222, elasticsearch 9200 (docker), redis 6379

# Tests — Rails is MINITEST, not RSpec
cd api && bin/rails test                          # full suite
cd api && bin/rails test test/models/post_test.rb # single file
pnpm test                                         # turbo run test (JS packages)
pnpm -F @campsite/web test                        # vitest
pnpm -F @campsite/sync-server test

# Lint / format (CI auto-commits fixes)
pnpm lint && pnpm format
cd api && bundle exec rubocop        # -A to autofix; shopify style, line max 240

# API client codegen — run after changing serializers/controllers
script/gen-client       # rake apigen/openapi → packages/types/generated.ts
```

CI truth: `.github/workflows/api-tests.yml` (rubocop + schema:load +
assets:precompile + rails test against MySQL 8/Redis/Elasticsearch) and
`client-build.yml` (`pnpm turbo run test --filter=@campsite/web`).

## Architecture Overview

Slack-alternative: Rails 8.1 API + Next.js web app + realtime services.

| Path | What |
|---|---|
| `api/` | Rails 8.1 API/admin/auth — MySQL (trilogy), Sidekiq 8 + sidekiq-scheduler, searchkick/Elasticsearch, Devise + Doorkeeper + Pundit, Blueprinter serializers, Flipper flags, Pusher realtime, `ruby_llm`, MCP server in `app/mcp/` (`mcp` gem, docs at `api/docs/mcp_server.md`) |
| `apps/web/` | Next.js 16 / React 19 main app (`app.campsite.test:3000`) |
| `apps/site/` | Marketing site (Next.js + Sanity) |
| `apps/sync-server/` | Hocuspocus/Yjs collaborative-editing WebSocket server |
| `apps/styled-text-server/` | Express service: Tiptap JSON ↔ HTML ↔ Markdown |
| `apps/integrations/`, `apps/figma/`, `apps/sanity-studio/` | integration surfaces, Figma plugin, CMS studio |
| `packages/` | shared libs; `types` holds the GENERATED API client (never hand-edit) |
| `html-to-image/` | Puppeteer screenshot service — own workspace, not in pnpm workspace |
| `config/deploy.campsite-*.yml`, `.kamal/` | Kamal deploy configs (homelab) |

Data flow: browser → Next.js → REST to Rails via generated `@campsite/types`
client; realtime via Pusher; collaborative docs via WebSocket to sync-server
(persists Yjs docs back to the Rails API); Rails calls styled-text-server and
html-to-image. External: S3 + Imgix, 100ms, Postmark, Slack/Linear/Figma/
Cal.com/Zapier, OpenAI.

Deployment: **Kamal to the homelab** — Odin `192.168.10.7` (apps, MySQL,
Redis), Shuri `192.168.20.14` (Elasticsearch), Cloudflare Tunnel ingress; full
design in `docs/deployment/homelab-production.md`. Worker deploys separately
from API by design (writer custody). Secrets preflight:
`mise exec -- script/check-campsite-kamal-secrets`. ⚠️ `api/CLAUDE.md` still
says Hatchbox and Fly leftovers exist (`api/fly.toml`, `script/prod-*`) — all
`deploy-*.yml` workflows are `.disabled`; deploys are operator-run Kamal.

## Conventions & Patterns

Rails:
- Minitest + minitest-spec-rails, FactoryBot, VCR, `Sidekiq.testing!(:fake)`;
  tests mirror `app/` (controllers are the bulk of coverage). Committed
  `focus` is blocked by the custom cop `api/test/custom_cops/no_focus.rb`.
- **No `app/services`** — logic lives in models + concerns
  (`commentable`, `eventable`, …), namespaced model dirs
  (`event_processors/`, `organization/`), jobs, and clients in `api/lib/`.
- Serializers: Blueprinter subclasses of `ApiSerializer` with the
  `api_field`/`api_association` DSL — this metadata FEEDS the OpenAPI/TS
  codegen, so run `script/gen-client` after changes.
- Controllers: `Api::V1::BaseController` + `extend Apigen::Controller`
  (`response model:`, `request_params do`); Pundit `verify_authorized`
  enforced; cursor pagination via `render_page`.

Frontend:
- TanStack Query v5 over the generated client (module-level query object +
  `useMutation`/invalidate pattern — see `apps/web/hooks/useArchiveProject.ts`);
  jotai atoms in `apps/web/atoms/`; `@/` alias = `apps/web`.
- One hook per file in `hooks/`; tests colocated in `__tests__/` or sibling
  `*.test.ts(x)`; Playwright specs in `apps/web/playwright/`.
- Prettier: no semicolons, single quotes, no trailing commas, width 120,
  sorted imports (builtins → react → third-party → `@campsite/*` → `@/*` →
  relative). ESLint flat configs from `packages/eslint-config-campsite`.
- pnpm workspace = `apps/*` + `packages/*`; dependency versions centralized
  in the **pnpm catalog** (`pnpm-workspace.yaml`) with `overrides` and
  `minimumReleaseAge` supply-chain policy — bump versions there.

Key docs: `MAINTENANCE.md`, `docs/deployment/homelab-production.md`,
`docs/editor-component-integration.md`, `api/docs/mcp_server.md`.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   bd dolt push
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->
