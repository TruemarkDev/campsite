# frozen_string_literal: true

# Base class for every Campsite MCP prompt.
#
# A prompt is a reusable, server-authored workflow template the user invokes from
# their MCP client. Unlike a tool, a prompt performs **no Campsite mutation and runs
# no inference** — `#template` returns a static set of messages that instruct the
# client to drive the existing tools. Prompts therefore need no OAuth write scope
# beyond `mcp` and never touch the database.
#
# Subclasses set `prompt_name`, `title`, `description`, and `arguments`, and implement
# `self.template(args)` returning an `MCP::Prompt::Result`. Argument values arrive as
# strings (per the MCP spec) and are interpolated into the instruction text.
class McpPrompt < MCP::Prompt
  class << self
    # Convenience: a single-user-message result whose text is the instruction body.
    def user_message_result(text)
      MCP::Prompt::Result.new(
        description: description,
        messages: [
          MCP::Prompt::Message.new(
            role: "user",
            content: MCP::Content::Text.new(text),
          ),
        ],
      )
    end

    # Build a prompt argument; values are always strings over the wire.
    def arg(name, description:, required: false)
      MCP::Prompt::Argument.new(name: name, description: description, required: required)
    end

    # `org_slug` is shared by every Campsite prompt, mirroring the tools' org scoping.
    def org_slug_arg
      arg(
        "org_slug",
        description: "Slug of the organization to work within. Call list_organizations to discover available slugs.",
        required: true,
      )
    end
  end
end
