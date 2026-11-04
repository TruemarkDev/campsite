# frozen_string_literal: true

module McpTools
  # Lists the user's direct/group message threads in an organization. Mirrors
  # Api::V1::MessageThreadsController#index.
  class ListMessageThreads < McpTool
    tool_name "list_message_threads"
    description "List the connected user's message threads (DMs and group chats) in an organization, most recent first."
    input_schema(org_scoped_schema)

    private

    def execute
      actor, organization, member = organization_context!
      authorize!(actor, organization, :list_threads?)
      raise ToolError, "You do not have a membership in this organization." unless member

      threads = member.non_project_message_threads
        .serializer_includes
        .order(last_message_at: :desc, id: :desc)

      data = serialize(MessageThreadInboxSerializer, { threads: threads }, organization: organization, member: member)
      data_response(data)
    end
  end
end
