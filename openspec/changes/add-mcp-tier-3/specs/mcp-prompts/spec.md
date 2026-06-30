## ADDED Requirements

### Requirement: Server advertises the prompts capability

The MCP server SHALL advertise the `prompts` capability (with `listChanged`) in the
`initialize` handshake and SHALL serve `prompts/list` and `prompts/get`, exposing a
catalog of Campsite workflow templates.

#### Scenario: Client discovers prompts support

- **WHEN** a client completes the `initialize` handshake
- **THEN** the server's advertised capabilities include `prompts`

### Requirement: Campsite workflow prompt catalog

The server SHALL expose at least `triage_inbox`, `draft_standup`, and
`summarize_thread` prompts via `prompts/list`, each with typed arguments, and
`prompts/get` SHALL return the prompt's messages. A prompt SHALL only orchestrate
existing tools and SHALL NOT itself perform any Campsite mutation; every tool name a
prompt references SHALL exist in the tool registry.

#### Scenario: Client lists workflow prompts

- **WHEN** a client calls `prompts/list`
- **THEN** the catalog includes `triage_inbox`, `draft_standup`, and
  `summarize_thread` with their argument definitions

#### Scenario: Client gets a prompt's messages

- **WHEN** a client calls `prompts/get` for a catalog prompt with its required
  arguments
- **THEN** the server returns the prompt's messages and performs no mutation

#### Scenario: Prompts reference only real tools

- **WHEN** the prompt catalog is loaded
- **THEN** every tool name referenced by a prompt exists in the tool registry
