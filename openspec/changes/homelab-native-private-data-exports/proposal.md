## Why

Homelab data exports currently stage content in the local S3-compatible object
store and then invoke an AWS Fargate packager that cannot read that store. The
feature therefore leaves failed export records and fragments behind, requires
irrelevant AWS credentials, and cannot deliver a valid private download.

## What Changes

- Store export fragments and archives in a dedicated private homelab bucket with
  an independent retention policy.
- Replace the AWS ECS/Fargate packager with an isolated, concurrency-one archive
  worker using the existing Rails/Sidekiq runtime.
- Fail exports when any resource fails instead of packaging partial data, and make
  archive scheduling and completion idempotent.
- Deliver completed archives through an authenticated API route that redirects to
  a short-lived private object URL.
- Remove the public callback, hardcoded CloudFront URL, and homelab dependency on
  AWS ECS credentials.
- Preserve the existing ZIP format, resource-selection rules, and two-day
  availability window.

## Capabilities

### New Capabilities

- `private-data-exports`: Private, homelab-native creation, delivery, failure,
  retention, and cleanup of organization, project, and member data archives.

### Modified Capabilities

None.

## Impact

- Rails models, jobs, policy, controller, routes, mail delivery, migrations, and
  data-export tests under `api/`.
- The API production image gains Debian Bookworm's `zip` package, the latest
  version available from the pinned base distribution (`3.0-13`).
- Homelab API and worker configuration gains a private export-bucket name and a
  dedicated export worker role/queue.
- The legacy `data-exporter/` AWS image and callback endpoint are retired.
- Deployment provisions `campsite-exports` on the existing S3-compatible endpoint;
  no AWS provider, Docker socket, public CDN route, or new external service is used.
