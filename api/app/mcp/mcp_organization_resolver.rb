# frozen_string_literal: true

# Shared org-resolution for MCP tools and resources.
#
# Resolves the connecting user's kept membership in `slug`, enforces the org's 2FA
# policy (the same gate as `Api::V1::BaseController#require_org_two_factor_authentication`,
# so MCP is never a bypass), sets the `Current` context, and returns
# `[actor, organization, membership]`. Any failure raises `error_class` with a
# user-facing message; callers pass their own error type (tools raise a tool-level
# error, resources raise a JSON-RPC error) so the message surfaces correctly.
module McpOrganizationResolver
  extend self

  def resolve!(context, slug, error_class)
    raise error_class, "An org_slug argument is required." if slug.blank?

    membership = context.membership_for(slug)
    unless membership
      raise error_class, "You are not a member of an organization with slug '#{slug}'."
    end

    organization = membership.organization
    user = context.user

    if organization.enforce_two_factor_authentication? && !user.otp_enabled?
      raise error_class,
        "This organization enforces two-factor authentication, which your account hasn't enabled. " \
          "Enable 2FA in Campsite to use this connection here."
    end

    Current.user = user
    Current.organization = organization
    Current.organization_membership = membership

    [context.actor, organization, membership]
  end
end
