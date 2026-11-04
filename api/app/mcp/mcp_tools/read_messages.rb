# frozen_string_literal: true

module McpTools
  # Reads recent messages in a thread the user can access. Mirrors
  # Api::V1::MessageThreads::MessagesController#index.
  class ReadMessages < McpTool
    tool_name "read_messages"
    description "Read recent messages in a message thread by its public id, most recent first."
    input_schema(org_scoped_schema(
      properties: {
        thread_id: { type: "string", description: "The public id of the message thread to read." },
      },
      required: ["thread_id"],
      paginated: true,
    ))

    private

    def execute
      actor, organization, member = organization_context!

      thread = MessageThread.serializer_includes.find_by!(public_id: input[:thread_id])
      authorize!(actor, thread, :list_messages?)

      page = paginate(thread.messages.kept.eager_load(:attachments, :sender), order: { id: :desc })
      data = serialize(MessagePageSerializer, page, organization: organization, member: member)
      data_response(data)
    end
  end
end
