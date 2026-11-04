# frozen_string_literal: true

module McpTools
  # Lets the client discover which organizations the connected user can act in.
  # Not org-scoped — this is how a client learns the `org_slug` values every other
  # org-scoped tool needs.
  class ListOrganizations < McpTool
    tool_name "list_organizations"
    description "List the organizations the connected user belongs to, including each organization's slug. " \
      "Use a slug as the org_slug argument to the other tools."
    input_schema(properties: {}, required: [])

    private

    def execute
      Current.user = user

      memberships = user.kept_organization_memberships
        .eager_load(organization: :admins)
        .order(position: :asc, id: :asc)

      data = serialize(PublicOrganizationMembershipSerializer, memberships, organization: nil, member: nil)
      data_response(data)
    end
  end
end
