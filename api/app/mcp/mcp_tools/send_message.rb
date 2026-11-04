# frozen_string_literal: true

module McpTools
  # Sends a message into an existing thread (DM or group chat) as the connected
  # user. Mirrors Api::V1::MessageThreads::MessagesController#create. Requires the
  # write_message scope.
  class SendMessage < McpTool
    tool_name "send_message"
    description "Send a message into an existing message thread (DM or group chat) as the connected user. " \
      "Find thread ids with list_message_threads. To @mention a member, use `<@member_public_id>` in content. " \
      "Requires the write_message scope."
    input_schema(org_scoped_schema(
      properties: {
        thread_id: { type: "string", description: "The public id of the thread to post into." },
        content: { type: "string", description: "The message body as HTML. Use `<@member_public_id>` to @mention a member." },
        reply_to: { type: "string", description: "Optional public id of a message in the thread to reply to." },
      },
      required: ["thread_id", "content"],
    ))

    private

    def execute
      require_scope!("write_message")
      actor, organization, member = organization_context!

      thread = MessageThread.serializer_includes.find_by!(public_id: input[:thread_id])
      authorize!(actor, thread, :create_message?)

      message = thread.send_message!(
        sender: member,
        content: enrich_mentions(input[:content]),
        reply_to: input[:reply_to].presence,
      )

      data_response(serialize(MessageSerializer, message, organization: organization, member: member))
    end
  end
end
