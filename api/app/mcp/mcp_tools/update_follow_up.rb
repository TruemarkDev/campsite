# frozen_string_literal: true

module McpTools
  class UpdateFollowUp < McpTool
    tool_name "update_follow_up"
    description "Reschedule one of the connected member's personal follow-ups."
    input_schema(org_scoped_schema(
      properties: { follow_up_id: { type: "string" }, show_at: { type: "string", format: "date-time" } },
      required: ["follow_up_id", "show_at"],
    ))

    private

    def execute
      actor, organization, member = organization_context!
      follow_up = member.follow_ups.serializer_preload.find_by!(public_id: input[:follow_up_id])
      authorize!(actor, follow_up, :update?)
      follow_up.update!(show_at: input[:show_at])
      data_response(serialize(FollowUpSerializer, follow_up, organization: organization, member: member))
    end
  end
end
