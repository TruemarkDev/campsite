# frozen_string_literal: true

module McpTools
  # Starts a new direct message or group chat with the given members, optionally
  # sending a first message. Mirrors Api::V1::MessageThreadsController#create.
  # Requires the write_message scope.
  class CreateMessageThread < McpTool
    tool_name "create_message_thread"
    description "Start a new direct message or group chat with one or more members, optionally with a first message. " \
      "Get member ids from list_members. Requires the write_message scope."
    input_schema(org_scoped_schema(
      properties: {
        member_ids: {
          type: "array",
          items: { type: "string" },
          description: "Public ids of the members to include (besides yourself).",
        },
        title: { type: "string", description: "Optional title for a group chat." },
        content: { type: "string", description: "Optional first message as HTML. Use `<@member_public_id>` to @mention." },
      },
      required: ["member_ids"],
    ))

    private

    def execute
      require_scope!("write_message")
      actor, organization, member = organization_context!
      authorize!(actor, organization, :create_thread?)

      members = organization.kept_memberships
        .where(public_id: Array(input[:member_ids]))
        .serializer_eager_load
        .to_a
      raise ToolError, "No valid members found for the given member_ids." if members.empty?

      members = (members + [member]).uniq

      thread = MessageThread.create!(
        title: input[:title],
        owner: member,
        event_actor: member,
        organization_memberships: members,
        group: members.size > 2,
        call_room: nil,
        project: nil,
        last_message_at: Time.current,
      )

      CreateMessageThreadCallRoomJob.perform_async(thread.id)

      if input[:content].present?
        thread.send_message!(sender: member, content: enrich_mentions(input[:content]))
      end

      data_response(serialize(MessageThreadSerializer, thread, organization: organization, member: member))
    end
  end
end
