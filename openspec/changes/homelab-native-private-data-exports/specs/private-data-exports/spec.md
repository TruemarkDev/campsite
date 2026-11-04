## Purpose

Provide authorized users with portable content archives that are created,
delivered, and expired entirely within the private homelab environment.

## ADDED Requirements

### Requirement: SyR-DEX-1 Export scope preserves authorized content boundaries

The system SHALL preserve the existing organization, project, and current-member
export scopes. Organization exports SHALL exclude private projects; project
exports SHALL require access to that project; current-member exports SHALL include
only content authored by that member. Exported JSON, attachments, recordings, and
transcripts SHALL retain the existing archive directory layout.

**Verification:** Test and Inspection.

#### Scenario: Organization export excludes private projects

- **WHEN** an authorized organization administrator requests an organization export
- **THEN** the archive contains public-project content and organization members but no private-project content

#### Scenario: Project export respects project access

- **WHEN** a member requests an export for a project they can view
- **THEN** the archive contains that project's channel metadata, published posts, notes, calls, attachments, recordings, and transcripts

#### Scenario: Current-member export is author-scoped

- **WHEN** a member requests their own export
- **THEN** the archive contains that member's profile and authored published posts but no content authored only by another member

### Requirement: SyR-DEX-2 Export data remains in private homelab storage

The system SHALL write export fragments and completed archives to a dedicated
private bucket on the configured homelab S3-compatible endpoint. Creating,
packaging, downloading, and deleting an export SHALL NOT require AWS ECS, ECR,
CloudFront, public object access, or provider credentials.

**Verification:** Inspection, Test, and Demonstration.

#### Scenario: Export completes without external provider access

- **WHEN** an export runs with only the homelab database, Redis, worker, and S3-compatible object store available
- **THEN** the export completes without making an AWS provider API call

#### Scenario: Export objects are isolated from media objects

- **WHEN** export resources are created
- **THEN** every fragment and archive is written beneath that export's prefix in the private export bucket rather than the media bucket

### Requirement: SyR-DEX-3 Archive completion is atomic and fail-closed

The system SHALL package an archive only after every resource has completed
successfully. Any terminal resource or archive error SHALL mark the export failed,
SHALL NOT send a completion email, and SHALL NOT expose a downloadable partial
archive. Duplicate completion checks and archive-job retries SHALL produce at most
one completed export and one completion email.

**Verification:** Test and Analysis.

#### Scenario: Resource failure prevents a partial archive

- **WHEN** any export resource reaches its terminal error state
- **THEN** the export enters the error state and no archive-completion email is sent

#### Scenario: Duplicate archive jobs are idempotent

- **WHEN** the archive job is delivered more than once for the same export
- **THEN** one archive is retained and one completion email is queued

#### Scenario: Successful resources enqueue isolated packaging

- **WHEN** the final pending resource completes and no resource has failed
- **THEN** the export enters the archiving state and is queued for isolated archive processing

### Requirement: SyR-DEX-4 Archive downloads require the requesting user

The system SHALL expose an authenticated download route only after an export
completes. Only the user who requested the export SHALL be authorized. A successful
request SHALL redirect to a short-lived private object URL with attachment
disposition; responses SHALL NOT use the public CDN or immutable public caching.

**Verification:** Test and Demonstration.

#### Scenario: Requester downloads a completed export

- **WHEN** the requesting user opens the download route for their completed export
- **THEN** the system redirects them to a short-lived private archive URL

#### Scenario: Another user is denied

- **WHEN** a different authenticated user requests the export download route
- **THEN** the system denies access without issuing an object URL

#### Scenario: Incomplete export is unavailable

- **WHEN** the requester opens the download route before completion or after failure
- **THEN** the system returns not found and does not issue an object URL

### Requirement: SyR-DEX-5 Export data expires after the download window

The system SHALL retain a completed archive for the existing two-day availability
window and then delete the export prefix and database record. Successful packaging
SHALL remove intermediate fragments, failed exports SHALL schedule cleanup, and the
private bucket SHALL have lifecycle expiration as a fallback for abandoned objects.

**Verification:** Test, Inspection, and Demonstration.

#### Scenario: Successful export cleanup

- **WHEN** the two-day cleanup job runs for a completed export
- **THEN** the archive, any remaining fragments, and the database record are deleted

#### Scenario: Failed export cleanup

- **WHEN** an export reaches a terminal error
- **THEN** cleanup is scheduled and no fragments remain beyond the bucket's lifecycle window
