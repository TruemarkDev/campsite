## 1. Stewardship and workspace gate

- [ ] 1.1 Obtain an explicit change to `MAINTENANCE.md` (or an explicit approved
      exception) permitting this feature, and verify the approval is recorded
      before any application code is edited.
- [ ] 1.2 Create a clean isolated worktree from the user-named integration
      branch, record `git branch --show-current` and the baseline SHA, and verify
      none of the dirty files listed in `design.md` A-9/RISK-7 are present in the
      feature diff.
- [ ] 1.3 Inspect Beads issue `campsite-4cl`, claim it only in the approved
      implementation worktree, and verify no Beads push, Git commit, push, or
      deployment is performed without its separate authorization gate.

## 2. Persistence and domain model

- [ ] 2.1 Add the default-false `oauth_applications.agent_capable` migration and
      model/update validation, and verify schema load plus model tests preserve
      all existing OAuth applications as non-agent integrations.
- [ ] 2.2 Add `project_beads_sources` with a unique project, opaque public id,
      connector OAuth application, opaque source project id, display name,
      current snapshot reference, and successful-ingest metadata; verify the
      migration applies and rolls back cleanly on an empty test database.
- [ ] 2.3 Add immutable `project_beads_snapshots` with source, schema/tool
      metadata, Beads branch/revision, collection/ingest timestamps, digest, and
      normalized payload; verify source-plus-digest uniqueness and current
      snapshot referential integrity in model tests.
- [ ] 2.4 Implement source validations that require the connector application
      to belong to the organization and have a kept project attachment, and
      verify cross-organization, detached, discarded, and duplicate-source
      cases fail without changing the current source.
- [ ] 2.5 Implement dependent source/snapshot cleanup for detach and channel
      deletion plus archived-channel ingest rejection, and verify model tests
      prove that none of those lifecycle actions calls or mutates Beads.
- [ ] 2.6 Confirm `DataExport` continues to exclude the Beads source, snapshots,
      and agent roster, and add an export regression test that inspects the
      delivered channel archive.

## 3. Authorization and API contracts

- [ ] 3.1 Add a Board read policy requiring a kept human or OAuth application
      project membership, and verify policy tests cover ordinary members,
      explicitly attached guests, public-channel `view-any` nonmembers, private
      nonmembers, discarded memberships, and attached connector applications.
- [ ] 3.2 Add feature-flagged source show/create/update/destroy routes and
      Apigen controllers using `manage_integrations?`, and verify controller
      tests cover one-source enforcement, safe empty states, replacement,
      detach cleanup, unauthenticated requests, and forbidden viewers.
- [ ] 3.3 Implement snapshot schema v1 validation with an explicit field
      allowlist, bounded strings/collections, unique opaque dotted ids,
      timestamp parsing, protocol version checks, digest verification, and
      coherent Ready/Blocked membership; verify fixture tests cover malformed,
      oversized, duplicate, unknown, and forbidden fields without persisting a
      partial snapshot.
- [ ] 3.4 Add the snapshot-ingest endpoint authorized to the source's exact
      connector OAuth application, and verify tests cover cross-app and
      cross-project denial, detached/discarded apps, idempotent repeat ingest,
      older collection timestamps, archived channels, atomic pointer updates,
      and last-good-snapshot retention.
- [ ] 3.5 Emit one project-scoped stale event only when a new snapshot becomes
      current, and verify job/controller tests prove rejected, repeated, and
      audit-only older snapshots emit no invalidation.
- [ ] 3.6 Add a dedicated Board response serializer containing only safe source
      metadata, current snapshot metadata, normalized cards, and safe blocker
      ids; verify the generated schema contains no repository path, Beads
      configuration, description, note, design, acceptance, comment, memory,
      infrastructure, or credential field.
- [ ] 3.7 Add a dedicated channel-agent summary serializer exposing only public
      id, display name, avatar URLs, `Attached`, `Agent`, and `Beads publisher`
      roles, and verify controller/schema tests never use or expose the full
      `OauthApplicationSerializer` or `WebhookSerializer` fields.
- [ ] 3.8 Add organization-admin API support for changing
      `agent_capable`, and verify authorization tests prevent ordinary members,
      guests, and OAuth application actors from changing the classification.
- [ ] 3.9 Run `script/gen-client` after the final serializer/controller
      metadata changes and verify `packages/types/generated.ts` is generated,
      formatted, and never hand-edited.

## 4. Repository-side Beads publisher

- [ ] 4.1 Implement a dependency-free publisher entrypoint with explicit API
      base URL, channel/source id, OAuth token environment variable, Beads
      binary, and repository-directory inputs; verify `--help` documents that it
      is one-shot and read-only and never prints the token or repository path.
- [ ] 4.2 Invoke only `bd --readonly -C <repo> context --json`, `vc status
      --json`, `export`, `ready --json`, and `blocked --json`, and verify command
      tests fail closed when the binary, workspace, command output, or expected
      source project id is missing or inconsistent.
- [ ] 4.3 Normalize regular issues to snapshot schema v1, strip every excluded
      field, derive mutually exclusive columns from native Ready/Blocked command
      membership, and verify fixtures cover ready, blocked, in-progress, closed,
      parent/child, safe dependency, unknown type/label, ANSI/control text, and
      opaque dotted ids.
- [ ] 4.4 Compute the canonical snapshot digest and publish it with bounded HTTP
      timeouts and non-interactive failure behavior, and verify contract tests
      cover accepted, idempotent, unauthorized, invalid, archived, and server
      unavailable responses without modifying the Beads workspace.
- [ ] 4.5 Run the publisher against a disposable fixture Beads workspace and
      compare `bd vc status`, `bd export`, and filesystem/Git state before and
      after; verify collection and a failed publication leave Beads and tracked
      exports unchanged.
- [ ] 4.6 Verify the publisher and Homebrew `bd` work under
      `env -i PATH=/opt/homebrew/bin:/usr/bin:/bin`, then document the official
      Beads source, installed/latest version, Homebrew update command, bare
      environment PATH, OAuth token custody, one-shot invocation, and
      operator-owned publication trigger in the deployment/operator docs (and
      `~/cli-tools.md` when the publisher is actually installed for this user).

## 5. Web Board and source setup

- [ ] 5.1 Add typed TanStack Query hooks for Board read, source management,
      snapshot freshness, agent roster, and agent classification, and verify
      hook tests cover scoped keys, feature-flag disablement, invalidation, and
      API error handling.
- [ ] 5.2 Add `/[org]/projects/[projectId]/board.tsx` using the existing project
      page provider/loading/404/title patterns, and verify route tests cover
      member, guest-member, public nonmember, private nonmember, archived, and
      feature-disabled states.
- [ ] 5.3 Extend `ProjectView` with Board after Calls, shortcut 4 on post
      channels and 3 on chat channels while preserving all current shortcuts;
      update the exact NavigationBar and split-view route predicates, and verify
      component tests cover normal/chat routes without changing unrelated Calls
      behavior.
- [ ] 5.4 Add an unattached Board state and source setup/replace/detach dialog
      for integration managers, including the allowlisted-data and channel
      audience warning, and verify viewers and guests never receive management
      controls.
- [ ] 5.5 Build the read-only Ready, In progress, Blocked, and Closed Board with
      accessible cards and no drag dependency or write affordance; verify tests
      cover state precedence, blocker ids, zero tasks, long titles, unknown safe
      metadata, and progressively revealed Closed work.
- [ ] 5.6 Add filters for id/title, type, priority, assignee, label, and Closed
      inclusion, and verify filtering changes rendered cards only and never
      sends a task mutation request.
- [ ] 5.7 Show exact source revision, collection time, ingest time, and distinct
      unattached/waiting/current/last-good-after-error states, and verify no UI
      string claims an unsupported sync SLA or up-to-date status.
- [ ] 5.8 Add the safe channel roster and organization integration
      `agent_capable` control, and verify generic integrations are not labeled as
      agents, publisher roles compose correctly, detached agents disappear, and
      every runtime-status label remains `Attached` rather than Online/Idle/
      Offline.
- [ ] 5.9 Subscribe to the project-scoped stale event and invalidate the Board
      query as one snapshot unit, and verify tests do not optimistically merge or
      reorder individual cards.
- [ ] 5.10 Verify desktop, mobile, keyboard, reduced-motion, and screen-reader
      behavior for the expanded view switcher, horizontal Board scrolling,
      filters, cards, source dialog, and roster; record any non-conformance
      inline rather than claiming completion.

## 6. Security, compatibility, and quality gates

- [ ] 6.1 Add publisher/API contract fixtures for unsupported schema versions,
      unknown Beads fields/statuses/types/dependencies, dependency cycles,
      duplicate and dotted ids, empty source, stale/older snapshot, auth failure,
      source mismatch, and revision conflict; verify every case fails closed or
      renders the documented safe fallback.
- [ ] 6.2 Inspect all Board and roster serializers plus generated TypeScript for
      secrets, redirect URIs, webhooks, provider data, filesystem paths, remote
      URLs, descriptions, notes, comments, memories, and infrastructure records;
      run `gitleaks detect` because OAuth/auth configuration is in scope and
      verify the report is clean without printing credential values.
- [ ] 6.3 Run focused Rails model, policy, controller, serializer, event, export,
      and publisher tests plus `bundle exec rubocop` on changed Ruby files, and
      verify every command passes under the declared Ruby/Node toolchain.
- [ ] 6.4 Run `script/gen-client`, Rails schema load/assets precompile/full test
      suite, `pnpm -F @campsite/web test`, relevant TypeScript/lint/format checks,
      and the web production build; verify failures are resolved or recorded as
      pre-existing with reproducible evidence.
- [ ] 6.5 Run `openspec validate add-channel-beads-board --strict`, inspect the
      final implementation against every SyR requirement and RISK mitigation,
      and verify the change remains read-only, dependency-free, and feature-
      flagged.

## 7. UAT, rollout, and close-out

- [ ] 7.1 In an approved non-production environment, attach a disposable Beads
      fixture to one private post channel and one chat channel, publish a known
      snapshot, and verify columns, filters, source metadata, shortcuts, agent
      roles, exact membership ACL, archive/unarchive, detach, and last-good
      failure behavior on desktop and mobile.
- [ ] 7.2 Verify public-channel nonmembers learn nothing about Board/source/
      agents, explicit guest members see only allowlisted data, and exported
      channel archives omit all Board and roster content; retain raw request and
      delivered-export evidence without credentials.
- [ ] 7.3 Recheck the exact revision, migration plan, API/web target configs,
      feature flag, service health checks, and rollback path before any release;
      deploy only after separate explicit authorization and verify API and web
      revisions independently (no worker deployment is required for push ingest).
- [ ] 7.4 Roll back the trial by disabling the feature flag and verify Board
      navigation and ingest stop while the external Beads workspace and its Dolt
      revision remain unchanged; delete cached source data only with separate
      explicit cleanup approval.
- [ ] 7.5 After every requirement, automated gate, authorized UAT, and required
      release proof is complete, close Beads issue `campsite-4cl`, run
      `git status`, and hand off changed files and evidence without committing,
      pushing, syncing Beads, or deploying beyond the authority granted for that
      implementation session.
