# frozen_string_literal: true

module McpTools
  # Lists the members of an organization, including each member's public id and
  # username — needed to @mention people (use the id as `<@member_public_id>`) and
  # to pick recipients for direct messages. Mirrors
  # Api::V1::OrganizationMembersController#index.
  class ListMembers < McpTool
    tool_name "list_members"
    description "List the members of an organization, including each member's id and username. " \
      "Use a member id with `<@member_public_id>` to @mention them, or as a recipient for create_message_thread."
    input_schema(org_scoped_schema(
      properties: {
        q: { type: "string", description: "Optional search query to filter members by name or username." },
      },
      paginated: true,
    ))

    private

    def execute
      actor, organization, member = organization_context!
      authorize!(actor, organization, :list_members?)

      memberships = organization.kept_memberships.serializer_eager_load
      memberships = memberships.search_by(input[:q]) if input[:q].present?

      page = paginate(policy_scope(actor, memberships), order: { last_seen_at: :desc, id: :desc })
      data = serialize(OrganizationMemberPageSerializer, page, organization: organization, member: member)
      data_response(data)
    end
  end
end
