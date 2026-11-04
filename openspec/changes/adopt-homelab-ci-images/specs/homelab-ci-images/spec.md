## ADDED Requirements

### Requirement: SwR-1 Reproducible homelab CI images
Homelab SHALL own image build sources, official artifact/version/digest pins,
tool smoke tests and publication provenance. Consuming workflows SHALL pin
published images by digest in the existing Forgejo registry.
Verification: Inspection and Test.

#### Scenario: Candidate image promotion
- **WHEN** a candidate image is selected for Campsite
- **THEN** its native amd64 smoke tests, tool versions, verified TLS checkout,
  security report, source revision and registry digest are recorded
- **AND** a retained previous digest provides a rollback candidate

### Requirement: SwR-2 Latest stable runtime parity
Campsite SHALL select latest stable Ruby and Node.js from official release
sources at implementation time, including Node Current, and align local, CI
and application image declarations. Project lockfiles SHALL own application
analyzer dependencies. Runtime selection SHALL exclude prereleases.
Verification: Inspection and Test.

#### Scenario: Runtime upgrade
- **WHEN** the runtime migration is validated
- **THEN** canonical pins, image metadata and all active runtime declarations agree
- **AND** relevant Rails/JS tests, typechecks, lint and production image builds
  have explicit results, with baseline failures identified separately

### Requirement: SwR-3 Authoritative checks and reliable PR feedback
CI SHALL preserve scanner failures independently of reviewdog publication.
Required checks SHALL bind to the analyzed commit. Publishing SHALL use trusted
code and scoped credentials without executing untrusted PR code.
Verification: Test and Demonstration.

#### Scenario: Finding and reporting lifecycle
- **WHEN** an authorized canary introduces a known finding, repeats a run and fixes it
- **THEN** the failure, PR comment, duplicate handling and fixed-state behavior
  are verified on the actual Forgejo instance
- **AND** stale-head and publication failures are visible without a false clean result

### Requirement: SwR-4 Cache isolation and performance evidence
CI caches SHALL invalidate by runtime/ABI and dependency inputs, isolate
untrusted writes and have bounded retention. Image acceleration SHALL preserve
job isolation and SHALL NOT share writable Docker state across daemons.
Verification: Inspection, Test and Analysis.

#### Scenario: Candidate benchmark
- **WHEN** candidate and baseline runs use the same source and test scope
- **THEN** repeated cold/warm stage timings, digests, cache state and sample
  counts demonstrate reduced setup overhead without dropped checks
- **AND** any concurrency, warm-worker or storage change has live capacity evidence

### Requirement: SwR-5 Controlled lifecycle and rollback
Image updates SHALL use tested candidates and reviewed consumer digest changes.
Real-host rollout SHALL follow the homelab confirmation policy. Publication,
provider execution, source validation and application deployment SHALL have
separate acceptance evidence. Vulnerability database freshness SHALL be reported.
Verification: Inspection and Demonstration.

#### Scenario: Failed canary
- **WHEN** a promoted candidate fails acceptance
- **THEN** retained image digests, version pins and scoped configuration backups
  restore the prior canary setup without deleting registry or shared cache data
- **AND** broader adoption remains unaccepted
