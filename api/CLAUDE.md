# CLAUDE.md — API (Rails backend)

This is the Rails API for Campsite, living in the `api/` folder of a monorepo
(`apps/`, `packages/`, `html-to-image/`, `sync-server/`, etc. sit alongside it).
This repo is a **fork of the open-source Campsite codebase**, maintained by
Truemark/Varicon. Some upstream tooling is now stale — see **Deployment** below.

## Stack

- **Ruby** 4.0.5 (`.ruby-version`), **Rails** 8.1, **Bundler** 4.x
- **Database**: MySQL via the **`trilogy`** adapter (PlanetScale-style). Not Postgres.
- **Background jobs**: Sidekiq 8.1 + `sidekiq-scheduler` (`config/sidekiq.yml`), Redis-backed
- **Search**: Elasticsearch
- **Realtime**: Pusher
- **Auth**: Devise + Doorkeeper (OAuth) + devise-two-factor
- **Authorization**: Pundit policies (`app/policies/`)
- **Serialization**: Blueprinter (`app/serializers/`)
- **Feature flags**: Flipper
- **Web server**: Puma 8 (`config/puma.rb`)

## Common commands

Run all of these from the `api/` directory.

```bash
bin/rails test                      # run the full test suite (Minitest)
bin/rails test test/models/x_test.rb   # run a single file
bin/rails db:migrate                # apply migrations
bin/rails g migration AddXToY x:integer
bundle exec rubocop                 # lint
bundle exec rubocop -A              # lint + autofix
```

**Run the whole dev environment** (API + web + workers + redis + asset watchers)
from the **monorepo root**, not here:

```bash
script/dev            # overmind start, driven by the root Procfile
```

The root `Procfile` starts the API with
`bundle exec rails server -p 3001 -b '127.0.0.1'`. API is served at
http://api.campsite.test:3001.

## Testing conventions

- **Minitest** (with `minitest-spec-rails`), not RSpec. Factories via FactoryBot
  (`test/factories/`). Test helper at `test/test_helper.rb`.
- To run a single test/group while developing, add `focus` above the `test`/`describe`.
- **Do not commit `focus`** — a custom RuboCop cop (`test/custom_cops/no_focus.rb`,
  required from `.rubocop.yml`) fails the build if you do.

## Linting

- RuboCop, inheriting `rubocop-shopify` + `rubocop-rails`, plus the local `no_focus` cop.
- `NewCops: enable`. `bin/`, `db/`, `script/`, `vendor/` are excluded.

## Deployment — Hatchbox, NOT Fly ⚠️

We deploy this API with **Hatchbox**. The upstream Campsite project deployed to
Fly.io, so this fork still contains Fly leftovers that are **stale / dead** and
must not be treated as the source of truth:

- `api/fly.toml` — upstream Fly config, unused
- `bin/rails fly:ssh` / `fly:console` (`lib/tasks/fly.rake`), and the root
  `script/prod-ssh` / `script/prod-console` that wrap them — Fly-specific, do not use
- `.github/workflows/deploy-*.yml.disabled` — all disabled
- The README's "Deploying" section (PlanetScale/Fly/GitHub Actions) is upstream docs

When asked about prod access, deploys, or rollbacks, use the Hatchbox workflow —
do not reach for the Fly tasks above.

### Puma bind

`config/puma.rb` binds via the `port` directive (`tcp://0.0.0.0:PORT`, default 3000)
— correct for local dev and for Hatchbox/nginx setups that proxy to a TCP port. To
serve over a Unix socket instead, set `PUMA_BIND`, e.g.
`PUMA_BIND="unix:///home/deploy/<app>/shared/sockets/puma.sock"`.

(Historical note: this previously hardcoded `bind "tcp://fly-local-6pn:..."` from
the upstream Fly deploy, which does not resolve on Hatchbox. Removed in favor of the
env-driven bind above.)

## Layout notes

- `app/models`, `app/controllers`, `app/jobs` (Sidekiq), `app/policies` (Pundit),
  `app/serializers` (Blueprinter), `app/mailers`
- `lib/tasks/` — rake tasks (`dev.rake`, `apigen.rake`/`openapi.rake` for API client
  generation, `demo_org.rake`, etc.)
- Email previews in dev: http://api.campsite.test:3001/preview-emails (letter_opener_web)
- Profiling: append `?pp=flamegraph` to a URL (rack-mini-profiler)
