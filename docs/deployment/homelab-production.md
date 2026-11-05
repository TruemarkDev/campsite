# Campsite homelab deployment

Campsite runs on the private `camp.home` network. Application data and search
use the PostgreSQL 18 Patroni cluster on Groot (`192.168.10.33`) and pg-b
(`192.168.10.35`), with an etcd witness on Quill (`192.168.10.32`). Quill
runs the API, two Sidekiq worker roles, web, sync, styled text, and image
rendering. Groot also runs Redis. Vyas supplies object storage and the
pgBackRest backup repository; Heimdall routes private traffic.

The former Mantis Elasticsearch VM and disks are removed. The old MySQL
container and data directory on Groot are removed; Friday's local development
runtime uses PostgreSQL. The verified final MySQL migration archive remains at
`/volume1/shared/backups/campsite/mysql/camp-home-mysql-final-20261030T143446Z.sql.gz`
on Vyas. It is recovery evidence, not a writable rollback database. See
[PostgreSQL search](postgresql-search.md) and the [cutover evidence](../reviews/postgresql-search-release-2026-11-04.md).

| Service | Deployment config | Host | Check |
| --- | --- | --- | --- |
| Rails API | `config/deploy.campsite-api.yml` | Quill | `/up` and authenticated API |
| Sidekiq worker and export | `config/deploy.campsite-worker.yml` | Quill | queue processing and export |
| Private Next.js web | `config/deploy.campsite-web-home.yml` | Quill | `https://camp.home` and browser flow |
| Sync server | `config/deploy.campsite-sync.yml` | Quill | WebSocket collaboration |
| Styled text | `config/deploy.campsite-styled-text.yml` | Quill | `/up` and conversion |
| HTML-to-image | `config/deploy.campsite-html-to-image.yml` | Quill | `/up` and render |
| PostgreSQL/Patroni | `config/deploy.campsite-pg.yml` | Groot, pg-b | leader, standby, SQL and backup |
| Redis | API Kamal accessory | Groot | PING and queue continuity |

Kamal is the application deployment control plane. `config/deploy.campsite-pg.yml`
contains a placeholder app server for accessory management; do not deploy that
placeholder app. The separate public web, marketing site, CMS, Figma plugin,
and integrations are outside this private core deployment.

## Release procedure

1. Identify the exact source revision and target, inspect pending migrations,
   verify Patroni leader/standby health, and take a pgBackRest checkpoint.
2. Use the ignored `mise.deploy.toml` deployment profile through
   `script/campsite-deploy`; verify the selected Kamal config and registry.
   Never copy or commit credential values.
3. Keep API and worker revisions aligned. Pause writers for any migration or
   backfill that needs it; deploy workers before resuming API traffic. The API
   Kamal command runs `db:migrate` before Puma.
4. Verify running image revisions, API `/up`, web sign-in, search, queue jobs,
   styled text, WebSocket edits, and upload/download. Keep prior images and
   database checkpoint until acceptance.

The deployment wrapper and exact commands are in `script/campsite-deploy` and
`config/deploy.campsite-*.yml`. [Search operations](postgresql-search.md) cover
index rebuilds. [Earlier platform evidence](../reviews/homelab-platform-history.md)
is retained for audit but is not the current deployment procedure.

The live MySQL retirement verified PostgreSQL readiness, pgBackRest check,
Redis health, and HTTP success for API and web. Full browser collaboration,
export, and upload acceptance after that retirement have not been rerun.
