# frozen_string_literal: true

module McpTools
  class CancelFollowUp < McpTool
    tool_name "cancel_follow_up"
    description "Cancel one of the connected member's personal follow-ups. This removes the reminder, not its subject."
    input_schema(org_scoped_schema(properties: { follow_up_id: { type: "string" } }, required: ["follow_up_id"]))

    private

    def execute
      actor, _organization, member = organization_context!
      follow_up = member.follow_ups.find_by!(public_id: input[:follow_up_id])
      authorize!(actor, follow_up, :destroy?)
      id = follow_up.public_id
      follow_up.destroy!
      data_response({ removed: true, follow_up_id: id })
    end
  end
end
