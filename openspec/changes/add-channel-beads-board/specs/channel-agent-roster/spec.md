## Purpose

Show which explicitly classified agent integrations are attached to a channel
without exposing integration configuration or presenting attachment as live
agent presence.

## ADDED Requirements

### Requirement: SyR-9 — Agent classification is explicit

The system SHALL allow an authorized organization integration manager to mark
an OAuth application as agent-capable. The default SHALL be false. A channel
agent roster SHALL include only agent-capable applications with a kept
attachment to that channel and SHALL identify the channel's Beads publisher as
a separate role.

**Verification:** Test

#### Scenario: Agent-capable application is attached

- **WHEN** an OAuth application is marked agent-capable and attached to the
  channel
- **THEN** the channel roster includes it with Agent and Attached labels

#### Scenario: Generic integration is attached

- **WHEN** an OAuth application is attached but not marked agent-capable and is
  not the channel's Beads publisher
- **THEN** the channel agent roster does not present it as an agent

#### Scenario: Beads publisher is attached

- **WHEN** an attached OAuth application is bound to the channel's Beads source
- **THEN** the roster identifies it as Beads publisher and also identifies it as
  Agent only when its explicit agent-capable classification is true

#### Scenario: Agent classification is removed

- **WHEN** an authorized manager clears an application's agent-capable
  classification
- **THEN** the application disappears from channel agent rosters unless it is
  separately shown as that channel's Beads publisher

### Requirement: SyR-10 — Roster projection is safe for channel viewers

The system SHALL authorize roster reads only for kept channel memberships and
SHALL expose only application public id, display name, avatar URLs, and channel
roles. It SHALL NOT expose client ids, client secrets, access or refresh
tokens, redirect URIs, webhook configuration, provider credentials, owner
metadata, or integration-management actions through the roster response.

**Verification:** Inspection + Test

#### Scenario: Channel viewer reads the roster

- **WHEN** an authenticated member authorized to view the channel opens its
  Board
- **THEN** the response contains only the safe roster projection for attached
  agents and the Beads publisher

#### Scenario: Non-member reads a channel roster

- **WHEN** a user without a kept channel membership requests its roster,
  including a user who can view the channel's public posts through a broad role
- **THEN** the system rejects the request without revealing agent names, ids,
  avatars, roles, or whether a Beads source exists

#### Scenario: Roster serializer is inspected

- **WHEN** the roster contract and generated client schema are inspected
- **THEN** no credential, redirect, webhook, provider, or management field is
  present

### Requirement: SyR-11 — Attachment is not reported as live availability

The roster SHALL label a listed integration as Attached and SHALL NOT infer
Online, Idle, Offline, available capacity, or current task execution from OAuth
tokens, webhooks, last-use timestamps, or project membership. Live presence MAY
be added only under a separate heartbeat contract.

**Verification:** Inspection + Demonstration

#### Scenario: Attached agent has not used a token recently

- **WHEN** an agent-capable application remains attached but has no recent token
  activity
- **THEN** the roster continues to say Attached and does not infer an offline or
  online state

#### Scenario: Attached agent is actively calling Campsite

- **WHEN** an agent-capable application makes recent API or MCP calls
- **THEN** the roster still says Attached and does not convert incidental token
  activity into a presence state

#### Scenario: Agent is detached from the channel

- **WHEN** the application's kept project attachment is removed
- **THEN** it no longer appears in that channel's roster even if the application
  still exists in organization settings
