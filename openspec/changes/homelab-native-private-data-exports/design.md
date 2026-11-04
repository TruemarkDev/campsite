## Context

See `proposal.md` for motivation. Rails already selects export resources and uses
Sidekiq to serialize JSON and copy media. Runtime S3 variables point homelab
services at `s3.camp.home`, but the final packaging step is hardcoded to AWS ECS
and a different bucket. The only live export record is a historical failed project
export; no restore/import consumer exists.

The repository is in stewardship mode. Adding Debian Bookworm's `zip` package is
an explicit, narrow exception authorized for this change; no application library
or external service is added. The package source of truth is Debian Bookworm main,
and the pinned Ruby base image resolves `zip` to version `3.0-13`.

## Goals / Non-Goals

**Goals:**

- Keep all export storage, processing, delivery, and cleanup inside the homelab.
- Preserve archive contents, paths, permissions, and the two-day availability
  contract.
- Isolate recording-heavy ZIP work from normal background jobs.
- Make failure, retries, and duplicate delivery explicit and idempotent.
- Ensure exported personal data is never served through the public CDN.

**Non-Goals:**

- Building an import/restore workflow or a database backup.
- Expanding the set of exported records.
- Keeping an AWS/ECS compatibility mode.
- Giving application containers access to the Docker socket.

## Decisions

### Use a separate private bucket on the existing S3 endpoint

`DATA_EXPORT_S3_BUCKET` identifies `campsite-exports`; endpoint and credentials
reuse the existing runtime S3 configuration. JSON and copied media go directly to
that bucket under `exports/<public-id>/`. Separating exports from `campsite-media`
allows a private policy and short lifecycle without affecting durable media.

Using the media bucket was rejected because the generic CDN can expose its keys
with year-long public caching. Copying fragments to AWS was rejected because it
adds provider credentials, data egress, and a second storage authority.

### Use an explicit export state machine

A migration adds a non-null integer state with `pending`, `archiving`, `completed`,
and `error` values. Existing completed records are backfilled to `completed`, and
incomplete records with errored resources are backfilled to `error`.

The final resource takes a row lock before moving a pending export to `archiving`
and enqueueing one archive job. A terminal resource error moves the export to
`error`. Archive retry exhaustion also moves it to `error`. Only `archiving` may
transition to `completed`.

### Package on a dedicated Sidekiq queue and role

The archive job uses queue `exports`. The normal worker's queue list does not
include it. A second Kamal role runs the same immutable Rails image with a
concurrency-one Sidekiq configuration, bounding simultaneous scratch-disk and CPU
use without a new service image.

The job downloads one export prefix into a temporary directory, invokes
`/usr/bin/zip` through an argument array rather than a shell, uploads the archive,
completes the export, and deletes intermediate objects. Retries overwrite the same
deterministic archive key. A retry after completion only finishes fragment cleanup.

A local one-shot Python container was rejected because Rails would need Docker
socket access or a new remote job-control service. A Ruby ZIP library was rejected
because the pinned distribution package already supplies the required format with
a smaller dependency surface.

### Deliver through authenticated Rails authorization

Completion email links point to
`GET /v1/organizations/:org_slug/data_exports/:id/download`. The route requires
the same user that requested the export and only resolves completed exports. It
redirects to a five-minute presigned URL from the private bucket with attachment
disposition. The email link remains usable for two days because each authorized
visit creates a fresh short-lived object URL.

The existing public callback and signed callback token are removed because the
archive worker shares the Rails database and can complete the record directly.

### Delete whole prefixes and retain a lifecycle fallback

Successful packaging removes fragments after the completed record and archive are
durable. The existing delayed cleanup deletes every object below the export prefix,
not only the ZIP, then deletes the record. Terminal failures schedule the same
cleanup. Bucket lifecycle expiration is configured longer than the two-day user
window so abandoned objects are eventually removed even if Sidekiq is unavailable.

## Risks / Trade-offs

- **Large recordings exhaust worker scratch disk** → run one archive at a time,
  stream object downloads to files, record disk use during UAT, and fail/retry
  without publishing a partial archive.
- **A process dies after upload but before database completion** → use a
  deterministic key and idempotent overwrite; a retry resumes the same transition.
- **A process dies after completion but before fragment deletion** → completed
  retries perform fragment cleanup, and bucket lifecycle is the final safety net.
- **Rollback makes new email links unavailable** → retain the new images and
  complete end-to-end UAT before enabling general use; rollback intentionally stops
  new export creation while private objects expire.
- **Bookworm `zip` is old upstream software** → use the distribution-maintained
  package from the pinned base image and include it in image vulnerability review.

## Migration Plan

1. Provision the private `campsite-exports` bucket and lifecycle policy on the
   existing homelab S3 endpoint without changing `campsite-media`.
2. Build API and worker images from one immutable revision.
3. Deploy the API so the additive state migration completes; verify old workers
   continue safely during the brief mixed window.
4. Deploy the normal worker and export-worker roles from the same revision.
5. Request a small project export, inspect the ZIP, verify authenticated download,
   then exercise cleanup with a disposable export.
6. Roll back API and worker to their captured prior images if migration, archive,
   authorization, or cleanup verification fails. The additive state column and
   private bucket are safe to leave in place during rollback.
