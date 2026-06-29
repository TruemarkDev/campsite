# frozen_string_literal: true

# Per-request identity passed to every MCP tool as the server context.
#
# The Doorkeeper access token's resource owner is the connecting User, and MCP
# tools act *as that user* — the same way the `/api/v1` REST API does for a signed-in
# user (`ApiActor.new(user:)`), NOT as the connector OAuth application. This matters
# for authorization: policies like MessageThreadPolicy treat an actor carrying an
# `application` as a bot and check app membership instead of the user's, so we
# deliberately build a user-scoped actor and resolve org membership ourselves.
#
# The token is still used to check granted OAuth scopes (e.g. `write_post`). It is
# user-scoped, so one connection is naturally multi-org: each tool passes an
# org_slug and we resolve the user's kept membership there.
class McpRequestContext
  attr_reader :token

  def initialize(token:)
    @token = token
  end

  def user
    @user ||= User.find(token.resource_owner_id)
  end

  # True when the token was granted the given OAuth scope (e.g. `:write_post`).
  def scope?(name)
    token.scopes.exists?(name.to_s)
  end

  # The Pundit actor — user-scoped, matching the v1 REST API for a signed-in user.
  def actor
    @actor ||= ApiActor.new(user: user)
  end

  # The user's kept membership in the org with the given slug, or nil. Mirrors
  # Api::V1::BaseController#current_organization_membership.
  def membership_for(slug)
    user.kept_organization_memberships
      .joins(:organization)
      .find_by(organization: { slug: slug })
  end
end
