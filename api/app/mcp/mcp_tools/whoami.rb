# frozen_string_literal: true

module McpTools
  # Reports the connected user's own identity plus their member public id in every
  # organization they belong to. The member id is what `<@member_public_id>`
  # mentions and direct-message recipients use. Mirrors
  # Api::V1::UsersController#show (the `/users/me` endpoint).
  class Whoami < McpTool
    tool_name "whoami"
    description "Return the connected user's identity and their member id in each organization they belong to. " \
      "Use a member id with `<@member_public_id>` to @mention yourself, or as a direct-message recipient."
    input_schema(properties: {})

    private

    def execute
      identity = JSON.parse(CurrentUserSerializer.render(user))

      memberships = user.kept_organization_memberships.map do |membership|
        {
          org_slug: membership.organization.slug,
          org_name: membership.organization.name,
          member_id: membership.public_id,
        }
      end

      data_response({ user: identity, memberships: memberships })
    end
  end
end
