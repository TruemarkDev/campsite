# frozen_string_literal: true

# The catalog of prompts advertised over MCP. Prompts are static workflow templates
# that orchestrate the registered tools and perform no mutation themselves (see
# McpPrompt) — every tool name a prompt references must exist in McpToolRegistry,
# which a test asserts.
module McpPromptRegistry
  extend self

  PROMPTS = [
    McpPrompts::TriageInbox,
    McpPrompts::DraftStandup,
    McpPrompts::SummarizeThread,
  ].freeze

  def prompts
    PROMPTS
  end
end
