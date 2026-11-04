# frozen_string_literal: true

module McpTools
  class RemoveMessage < McpTool
    tool_name "remove_message"
    description "Discard a message the connected user may remove. Requires write_message."
    input_schema(org_scoped_schema(
      properties: { thread_id: { type: "string" }, message_id: { type: "string" } },
      required: ["thread_id", "message_id"],
    ))

    private

    def execute
      require_scope!("write_message")
      actor, organization, member = organization_context!
      thread = MessageThread.serializer_includes.find_by!(public_id: input[:thread_id])
      raise ActiveRecord::RecordNotFound unless thread.organization == organization
      message = thread.messages.find_by!(public_id: input[:message_id])

      authorize!(actor, message, :destroy?)
      thread.discard_message!(actor: member, message: message)
      data_response({ removed: true, message_id: message.public_id })
    end
  end
end
