# frozen_string_literal: true

module McpTools
  class ListFollowUps < McpTool
    tool_name "list_follow_ups"
    description "List the connected member's pending personal follow-ups, earliest first."
    input_schema(org_scoped_schema(paginated: true))

    private

    def execute
      actor, organization, member = organization_context!
      scope = policy_scope(actor, member.unshown_follow_ups.serializer_preload)
      page = paginate(scope, order: { show_at: :asc, id: :asc })
      data_response(serialize(FollowUpPageSerializer, page, organization: organization, member: member))
    end
  end
end
