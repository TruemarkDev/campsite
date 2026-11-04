# frozen_string_literal: true

module McpTools
  class UpdateMessage < McpTool
    tool_name "update_message"
    description "Update a message the connected user may edit. Requires write_message."
    input_schema(org_scoped_schema(
      properties: { thread_id: { type: "string" }, message_id: { type: "string" }, content: { type: "string" } },
      required: ["thread_id", "message_id", "content"],
    ))

    private

    def execute
      require_scope!("write_message")
      actor, organization, member = organization_context!
      thread = MessageThread.serializer_includes.find_by!(public_id: input[:thread_id])
      raise ActiveRecord::RecordNotFound unless thread.organization == organization
      message = thread.messages.find_by!(public_id: input[:message_id])

      authorize!(actor, message, :update?)
      thread.update_message!(actor: member, message: message, content: enrich_mentions(input[:content]))
      data_response(serialize(MessageSerializer, message.reload, organization: organization, member: member))
    end
  end
end
