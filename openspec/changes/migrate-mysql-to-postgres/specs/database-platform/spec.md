## Purpose

Define the behaviour the relational store must preserve for users and
operators regardless of database engine, and the verification, backup and
rollback obligations for moving Campsite from MySQL to PostgreSQL.

## ADDED Requirements

### Requirement: SyR-PG-1 Identity matching stays case-insensitive

The system SHALL treat email addresses, usernames and organization slugs as
case-insensitive for lookup and for uniqueness, at both the application and
database-constraint level, on every supported database engine. A value that
differs from an existing one only by letter case SHALL be rejected as a
duplicate, and SHALL find the existing record on lookup.

**Verification:** Test.

#### Scenario: Sign-in with differently cased email

- **WHEN** a user registered as `ada@example.com` signs in or is matched by an OAuth provider as `Ada@Example.COM`
- **THEN** the existing user is found and no second user is created

#### Scenario: Case-only duplicate is rejected by the database

- **WHEN** a record is inserted directly, bypassing model validations, with an email, username or organization slug that differs from an existing row only by case
- **THEN** the database rejects the insert with a uniqueness violation

#### Scenario: Invitation and bounce matching ignore case

- **WHEN** an organization invitation or email-bounce record exists for `ada@example.com` and the system checks `ADA@example.com`
- **THEN** the existing invitation or bounce is matched

### Requirement: SyR-PG-2 Cursor pagination is complete and stable across NULLs

Cursor-paginated API lists SHALL return every matching record exactly once
across consecutive pages, in the same order they are returned today, including
when the sort column contains NULL values. Where records share NULL sort values,
they SHALL be ordered after non-NULL values in descending lists and before
non-NULL values in ascending lists, matching current MySQL behaviour.

**Verification:** Test.

#### Scenario: Descending walk across a NULL tail

- **WHEN** a client pages through a descending list whose sort column is NULL for some records, using `next_cursor` until exhausted
- **THEN** the union of pages equals the full result set with no duplicates or omissions, and the NULL-valued records appear last

#### Scenario: Same order on both engines

- **WHEN** the same fixture data is paginated on MySQL and on PostgreSQL
- **THEN** both engines return identical record order and identical page boundaries

### Requirement: SyR-PG-3 Bulk upserts update rather than fail on natural keys

Bulk recording of post views and attachment reordering SHALL update the
existing row when an incoming row matches it on the table's unique business
key, and SHALL NOT raise a uniqueness error or create a duplicate row.

**Verification:** Test.

#### Scenario: Repeated post view

- **WHEN** the same member's view of the same post is recorded twice in separate batches
- **THEN** exactly one post-view row exists and its timestamps and counters reflect the latest batch

### Requirement: SyR-PG-4 Time-zone-dependent scheduling is engine-independent

Notification schedules and scheduled notifications SHALL fire according to the
user's or record's IANA time zone, day of week and delivery offset, with
identical results on MySQL and PostgreSQL, and SHALL NOT depend on
database-server time-zone tables being loaded.

**Verification:** Test.

#### Scenario: Schedule applies at end time in the user's zone

- **WHEN** a user in `Asia/Kathmandu` has a weekday schedule ending at 18:00 and the current time is 18:05 on a Monday in that zone
- **THEN** the schedule is selected for applying, once per local day

#### Scenario: Day boundary differs from UTC

- **WHEN** it is Sunday in UTC but already Monday in the user's time zone
- **THEN** the schedule is evaluated against Monday's setting

### Requirement: SyR-PG-5 Cutover preserves every row and identifier

The migration to PostgreSQL SHALL preserve every row of every application
table, every primary-key value and every `public_id`, and SHALL leave the
schema version unchanged. Cutover SHALL NOT be accepted until per-table row
counts and per-table content checksums match between the final MySQL source
and the PostgreSQL target, and authenticated application reads return the
recorded critical counts.

**Verification:** Analysis and Demonstration.

#### Scenario: Verified copy

- **WHEN** the final data copy completes
- **THEN** a verification report shows equal row counts and equal checksums for every table, and the PostgreSQL schema version equals the MySQL source version

#### Scenario: New inserts do not collide

- **WHEN** a new record is created in any table immediately after cutover
- **THEN** it receives a primary key greater than every migrated key

#### Scenario: Search indexes remain valid

- **WHEN** a search runs after cutover without a reindex
- **THEN** results resolve to the same records they resolved to before cutover

### Requirement: SyR-PG-6 Cutover is reversible without data loss before acceptance

Until cutover is accepted, the operator SHALL be able to return service to the
untouched MySQL source by configuration change and redeploy of the previous
release alone. The MySQL source volume
SHALL NOT be mutated or deleted by the migration. Writes accepted by PostgreSQL
after reopening service and before a rollback are explicitly not carried back.

**Verification:** Demonstration.

#### Scenario: Rollback during the window

- **WHEN** verification fails before writers are restarted against PostgreSQL
- **THEN** restoring the previous database URLs and restarting writers returns the application to its pre-cutover state with no data loss

### Requirement: SyR-PG-7 PostgreSQL backups are restorable to a point in time

From the start of the shadow run, the system SHALL (a) continuously archive
WAL and take physical base backups sufficient to restore the database to any
point inside the recorded point-in-time-recovery window, and (b) take a
consistent, checksummed logical backup at least daily. Both SHALL be written
outside the database hosts, to the existing backup namespace, and retained
according to the retention policy recorded in `design.md` (D11). Archiving
SHALL continue across a Patroni failover without manual intervention. A backup
SHALL NOT be accepted until a restore into a disposable PostgreSQL instance
reproduces the recorded schema version and critical row counts. A streaming
replica SHALL NOT count as a backup.

**Verification:** Demonstration.

#### Scenario: Logical restore rehearsal

- **WHEN** the most recent logical backup is restored into a disposable instance
- **THEN** its schema version and critical row counts match the database at backup time

#### Scenario: Point-in-time recovery

- **WHEN** a row is deleted at time T and the operator restores to T minus one minute into a disposable instance
- **THEN** the deleted row is present and no transaction committed after the target time is present

#### Scenario: Archiving survives failover

- **WHEN** the Patroni leader changes
- **THEN** WAL archiving resumes from the new leader and the point-in-time-recovery window has no gap

### Requirement: SyR-PG-9 The shadow environment has no external side effects

The PostgreSQL shadow environment SHALL NOT send email, push notifications,
realtime events to production channels, webhooks or third-party integration
calls, and SHALL NOT write to production object-storage keys or production
search indexes. It SHALL be reachable only on the private homelab network under
its own hostname.

**Verification:** Inspection and Demonstration.

#### Scenario: Action that normally notifies

- **WHEN** a user creates a post that mentions a member in the shadow environment
- **THEN** no email, push or Pusher event reaches the member, and production search results are unchanged

#### Scenario: Upload in the shadow environment

- **WHEN** a file is uploaded in the shadow environment
- **THEN** the object is written under the shadow-only bucket or prefix and not under any production key

### Requirement: SyR-PG-10 Cutover follows a sustained parallel run

Cutover SHALL NOT begin until the shadow environment has run for at least 30
consecutive days, during which every `main` release was also deployed to it,
the nightly refresh and parity check (SyR-PG-5) passed on every run after the
first week, at least one planned switchover and one unplanned failover drill
(SyR-HA-2) passed, and at least one point-in-time recovery drill (SyR-PG-7)
passed. A failing night restarts the consecutive-pass count, not the 30 days.

**Verification:** Analysis.

#### Scenario: Readiness review

- **WHEN** the operator proposes a cutover date
- **THEN** the shadow-run log shows ≥30 days, one deploy per `main` release, the parity history, and the drill results, and any unmet item blocks the cutover

### Requirement: SyR-PG-11 MySQL remains restorable after cutover

After cutover acceptance, the stopped MySQL volume and the final checksummed
MySQL dump SHALL be retained unmodified for at least 30 days. The final dump
SHALL then be archived and the volume deleted only by a separate, recorded
operator decision.

**Verification:** Inspection.

#### Scenario: Late-discovered defect

- **WHEN** a data defect traced to the migration is discovered 20 days after cutover
- **THEN** the original MySQL data is still available to compare against or recover from

### Requirement: SyR-PG-8 Schema migrations are atomic

On PostgreSQL, a schema migration that fails partway SHALL leave the schema and
the schema-version table exactly as they were before the migration began, except
for migrations explicitly marked non-transactional (for example concurrent index
builds).

**Verification:** Test.

#### Scenario: Failing migration rolls back

- **WHEN** a migration adds a column and then raises an error
- **THEN** the column does not exist afterwards and the migration version is not recorded
