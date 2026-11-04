## 1. Private storage and lifecycle state

- [x] 1.1 Add the export state migration and model transitions; verify migration tests cover completed/error backfill and legal state changes
- [x] 1.2 Route export JSON, attachments, cleanup, and presigning through `DATA_EXPORT_S3_BUCKET`; verify model tests never write export objects to `S3_BUCKET`
- [x] 1.3 Make terminal resource errors fail the export and schedule cleanup; verify retries cannot package a partial export

## 2. Homelab archive processing

- [ ] 2.1 Add Debian Bookworm `zip` to the production image and a concurrency-one export Sidekiq config; verify the built image resolves `/usr/bin/zip` in a bare environment
- [x] 2.2 Implement the idempotent export archive job; verify a real ZIP contains the expected directory layout and duplicate delivery sends one completion email
- [x] 2.3 Remove the ECS task launcher, public callback route/controller/tests, and legacy Python exporter; verify repository search finds no runtime AWS ECS export dependency

## 3. Private download delivery

- [x] 3.1 Add requester-only download authorization and route; verify requester redirect, cross-user denial, and incomplete/error not-found behavior
- [x] 3.2 Replace the CloudFront mail URL with the authenticated download URL and a five-minute private presigned object URL; verify attachment disposition and expiry parameters
- [x] 3.3 Delete whole export prefixes on success/failure cleanup; verify fragments, archive, and database record are removed without touching media objects

## 4. Homelab deployment configuration

- [x] 4.1 Add `campsite-exports` configuration to API/worker and a dedicated export worker role; verify Kamal renders the expected bucket, queue, host, and secrets without values
- [ ] 4.2 Provision the private bucket and lifecycle idempotently in homelab; verify bucket access is private and expiration is longer than the two-day user window

## 5. Validation and release

- [x] 5.1 Run strict OpenSpec validation, focused Rails tests, full Rails tests, RuboCop, Zeitwerk, Brakeman, bundle-audit, and Gitleaks; record exact results
- [ ] 5.2 Commit only the reviewed export scope, merge into the current branch without pushing, and build API/worker from one clean immutable SHA
- [ ] 5.3 Deploy API, normal worker, and export worker to Odin; verify exact image digests, migrations, routes, restart counts, locks, and clean logs
- [ ] 5.4 Demonstrate project export end to end against homelab storage: request, archive, email, authenticated download, ZIP inspection, denial, and cleanup
