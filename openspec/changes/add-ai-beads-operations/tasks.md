## 1. Prerequisites and stewardship gate

- [ ] 1.1 Obtain an explicit `MAINTENANCE.md` policy change or approved
      exception, and verify `add-channel-beads-board` is implemented and proven
      before editing operation code.
- [ ] 1.2 Create a clean isolated worktree from the user-named integration
      branch; record branch/SHA and ensure no unrelated dirty work is absorbed.
- [ ] 1.3 Inspect and claim Beads issue `campsite-4cl.1` only in the authorized
      implementation lane; do not commit, push, run `bd dolt push/pull`, deploy,
      or enable a remote mutation without its separate authority gate.
- [ ] 1.4 Re-run the tool-adoption ritual against official Beads docs and the
      installed binary: origin, installed/latest version, changelog gap, native
      create/update/close/reopen/dependency/metadata/sandbox behavior, bare-PATH
      execution, and operator documentation.

## 2. Operation, authorization, and audit domain

- [ ] 2.1 Add additive operation, attempt/lease, approval, safe receipt, and
      source-specific agent-grant persistence behind a disabled feature flag;
      verify migrations load and roll back without changing existing sources.
- [ ] 2.2 Add versioned action schemas and validators for create first, then
      independently gated update, claim, close/reopen, and dependency actions;
      reject raw flags, shell, paths, remotes, force, bulk, custom ids, unsupported
      types, infrastructure, memory, workflow, config, SQL, Git, and sync fields.
- [ ] 2.3 Add `operate_beads?` policy and a dedicated `write_beads` Doorkeeper
      scope/consent label; verify initiating-user authorization, OAuth scope,
      agent classification, kept membership, and source/action grant are all
      independent gates.
- [ ] 2.4 Implement `suggest_only`, `approval_required`, and disabled-by-default
      `bounded_autonomous` grants with action/rate/field limits and audit events;
      verify no organization-wide or agent-classification implicit grant exists.
- [ ] 2.5 Implement operation state transitions, one-active-source lease,
      cancellation request, expiry, Conflict, Unknown, and safe audit retention;
      verify invalid transitions and cross-source/app/attempt completions fail.
- [ ] 2.6 Define and test receipt serializers that omit repository paths,
      environment, credentials, emails, raw argv/output, stack traces, excluded
      Beads content, and hidden model context.
- [ ] 2.7 Implement archive/detach/replacement/token/grant/flag lifecycle
      cancellation and reconciliation; verify no cleanup action calls Beads or
      issues a compensating mutation.

## 3. Source-bound repository executor

- [ ] 3.1 Extend the dependency-free publisher or add a sibling executor with
      explicit one-source configuration and bounded one-shot/long-poll modes;
      verify queue payloads cannot override API URL, token env var, binary,
      repository directory, or source project id.
- [ ] 3.2 Implement claim/lease and re-check `bd context --json` plus `bd vc
      status --json` before every attempt; verify mismatched source, revision,
      schema/tool compatibility, detached source, and expired attempt write
      nothing.
- [ ] 3.3 Build exact argv/stdin adapters using `bd --sandbox --actor <opaque>
      -C <configured-repo> ... --json`, create-only first; snapshot argv and
      process environment in tests and prove no shell, Git, Dolt sync, or
      unsupported Beads command executes.
- [ ] 3.4 Attach opaque `campsite_operation_id` metadata on create and reconcile
      using exact metadata search including closed work; test zero, one exact,
      one mismatched, multiple, lost receipt, expired lease, and retry cases.
- [ ] 3.5 Add source/target preconditions and action-specific before/after
      verification; permit only documented safe create rebase and mark
      unprovable outcomes Unknown without blind retry.
- [ ] 3.6 Submit redacted receipts and publish a fresh atomic Board snapshot
      after verified success; test mutation-success/snapshot-failure and
      receipt-failure/reconciliation independently.
- [ ] 3.7 Run against disposable embedded and server-mode fixtures with failure
      injection at claim, before command, after command, during receipt, and
      during snapshot; compare Git status, remote refs, Dolt revision, issues,
      and process logs without exposing credentials.
- [ ] 3.8 Verify under `env -i PATH=/opt/homebrew/bin:/usr/bin:/bin`, document
      install/update origin and execution custody in operator docs and
      `~/cli-tools.md` only when actually installed, and ensure no custom
      scheduler duplicates a supported first-party mechanism.

## 4. Human Board operation experience

- [ ] 4.1 Add source operation-capability/status endpoints and typed TanStack
      Query hooks; regenerate `packages/types/generated.ts` through
      `script/gen-client` and never hand-edit it.
- [ ] 4.2 Add an accessible New Bead form with exact source/repository-audience
      disclosure, bounded fields, parent/dependency lookup, duplicate candidates,
      source revision, and approval digest; verify edit invalidates approval.
- [ ] 4.3 Show truthful Pending, Claimed, Succeeded, Failed, Conflict, Expired,
      Cancelled, Unknown, and Applied/Board-refresh-pending states; never display
      a fabricated Beads id or optimistically move a card.
- [ ] 4.4 Add disabled/revoked/executor-unavailable/conflict recovery states and
      pending-only cancellation; verify unauthorized viewers learn nothing about
      source, grants, operations, or agents.
- [ ] 4.5 Add action UI one at a time after create: update, claim, close/reopen,
      add/remove dependency; verify each uses current target preconditions and a
      new approval when the normalized payload changes.

## 5. Native AI drafting and MCP tools

- [ ] 5.1 Select/reuse the existing Rails AI abstraction only after provider,
      version, privacy, structured-output, timeout, and target-environment checks;
      document model/provider and prompt/response retention rather than inventing
      a new model client.
- [ ] 5.2 Implement Draft with AI using user instruction plus explicitly selected,
      server-reauthorized bounded channel objects; exclude unselected history,
      attachments, linked pages, secrets, hidden prompts/reasoning, and private
      URLs from model and Beads payloads.
- [ ] 5.3 Validate structured model output through the same operation schema,
      present exact outgoing fields/citations/provider disclosure, and test
      hallucinated ids/types, prompt injection, oversize text, secrets, stale
      access, source mismatch, and duplicate suggestions.
- [ ] 5.4 Add MCP Board/source read tools and `create_bead` first, requiring
      `mcp`, `write_beads`, initiating-user Pundit policy, source grant, and
      configured approval mode; return queue state/receipt truthfully.
- [ ] 5.5 Add update/claim/close/reopen/dependency MCP tools only when their
      corresponding action is enabled and proven; verify `tools/list` omits
      disabled and every raw/destructive/repository/sync tool.
- [ ] 5.6 Extend the safe roster with Can suggest Beads work / Can operate Beads
      roles derived from grants, while preserving Attached rather than presence
      or availability claims.
- [ ] 5.7 Keep bounded-autonomous mode disabled through initial rollout; if later
      approved, test per-source action/rate/field limits, revocation races,
      repeated agent calls, and human-visible audit/kill switch.

## 6. Security and quality gates

- [ ] 6.1 Threat-test command injection, path/URL/environment override, prompt
      injection, cross-org/source/app access, confused deputy, token/grant
      revocation, lease theft, replay, approval digest tampering, and raw error
      leakage; prove each fails before or safely reconciles after a write.
- [ ] 6.2 Test reverse disclosure from private messages/posts/notes/transcripts/
      attachments into a broader repository; inspect model requests, operation
      payloads, receipts, logs, snapshots, serializers, and generated types.
- [ ] 6.3 Run `gitleaks detect` because OAuth, executor configuration, and AI
      provider handling are in scope; retain a clean report without printing
      credential values.
- [ ] 6.4 Run focused Rails model/policy/controller/MCP/executor tests, RuboCop on
      changed Ruby, web unit/accessibility tests, TypeScript/lint/format, API
      client codegen verification, and production builds under declared tools.
- [ ] 6.5 Run full Rails and web suites, schema load/assets precompile, publisher
      regression tests, and `openspec validate add-ai-beads-operations --strict`;
      classify any unrelated failure with reproducible evidence.

## 7. UAT, rollout, and handoff

- [ ] 7.1 In an approved non-production environment, use a disposable private
      channel and Beads workspace with remote auto-push disabled; test human
      create from draft through receipt and fresh snapshot on desktop/mobile.
- [ ] 7.2 Test an attached MCP agent in suggest-only and approval-required modes,
      including exact disclosure, scope/Pundit/grant denial, conflicts, executor
      outage, lost receipt, duplicate reconciliation, and revocation.
- [ ] 7.3 Verify no Git commit/push, `bd dolt push/pull`, remote-ref change,
      deployment, code edit, or unsupported Beads record occurs during product
      operation UAT; retain before/after evidence and rollback steps.
- [ ] 7.4 Release create-only behind separate server, executor, UI, AI, MCP, and
      bounded-autonomy flags after explicit deployment authority; verify exact
      API/web revision, health, public/private authorization, executor custody,
      and feature-disable rollback.
- [ ] 7.5 Enable later action grants individually only after their tests/UAT;
      leave unresolved open questions and any non-conformance marked inline.
- [ ] 7.6 Close `campsite-4cl.1` only after every enabled requirement and gate is
      proven; run `git status` and hand off without committing, pushing, syncing
      Beads, or deploying beyond the authority granted for that session.
