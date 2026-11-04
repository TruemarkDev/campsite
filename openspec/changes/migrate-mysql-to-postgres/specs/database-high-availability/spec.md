## Purpose

Keep Campsite's PostgreSQL database available and durable across the loss or
maintenance of a single database member, with clients always writing to the
single current leader.

## ADDED Requirements

### Requirement: SyR-HA-1 Exactly one writable leader

The cluster SHALL have at most one member accepting writes at any time. Leader
election SHALL require a majority of a three-member distributed configuration
store. A member that loses contact with the store majority SHALL stop
accepting writes.

**Verification:** Test (fault injection) and Inspection.

#### Scenario: Network partition of the leader

- **WHEN** the current leader loses connectivity to the other database member and to the store majority
- **THEN** it demotes itself to read-only, the reachable member is promoted, and no write is accepted by both members

#### Scenario: Loss of store quorum

- **WHEN** two of the three store members are unavailable
- **THEN** no promotion occurs and an alert is raised

### Requirement: SyR-HA-2 Failover and switchover are bounded and observable

On unplanned loss of the leader, a healthy replica SHALL be promoted within 60
seconds. A planned switchover SHALL complete with at most 30 seconds of write
unavailability. Each leader change SHALL be recorded and SHALL raise an alert.

**Verification:** Demonstration (drill with timing evidence).

#### Scenario: Leader VM is powered off

- **WHEN** the leader's VM is hard powered off
- **THEN** the replica is promoted within 60 seconds and the application resumes serving writes without configuration changes

#### Scenario: Planned maintenance

- **WHEN** the operator performs a switchover before patching the leader's host
- **THEN** writes are unavailable for no more than 30 seconds and the former leader rejoins as a replica after it restarts

### Requirement: SyR-HA-3 Clients follow the leader without redeploys

Every Campsite database client (API, worker, console, migrations) SHALL
connect only to the current leader. After a leader change, clients SHALL reach
the new leader on reconnect without an environment or deploy change. Reads
SHALL NOT be routed to replicas.

**Verification:** Demonstration.

#### Scenario: Worker after failover

- **WHEN** a failover happens while Sidekiq is processing jobs
- **THEN** in-flight jobs that fail are retried by Sidekiq and succeed against the new leader

#### Scenario: Replica never serves writes or reads

- **WHEN** a client connects while both members are healthy
- **THEN** the session reports `pg_is_in_recovery() = false`

### Requirement: SyR-HA-4 Replication loss is bounded

In normal operation, a commit acknowledged to the application SHALL be present
on the replica. When the replica is unavailable, the leader SHALL continue
accepting writes, and the loss of acknowledged commits on a subsequent
failover SHALL be bounded by the configured maximum replication lag. A replica
lagging beyond that bound SHALL NOT be promoted automatically.

**Verification:** Test and Inspection.

#### Scenario: Replica down, leader keeps serving

- **WHEN** the replica is stopped
- **THEN** the application keeps writing, an alert is raised, and the cluster reports the replica as unavailable

#### Scenario: Lagging replica not promoted

- **WHEN** the leader fails while the replica's lag exceeds the configured maximum
- **THEN** no automatic promotion occurs and the operator is alerted to decide
