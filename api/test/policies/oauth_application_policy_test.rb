# frozen_string_literal: true

require "test_helper"

class OauthApplicationPolicyTest < ActiveSupport::TestCase
  test "does not treat a user-owned application as organization-owned" do
    user = create(:user)
    application = create(:oauth_application, owner: user)

    assert_not Pundit.policy!(user, application).update?
  end

  test "allows an organization member with OAuth application permission" do
    membership = create(:organization_membership, :member)
    application = create(:oauth_application, owner: membership.organization)

    assert Pundit.policy!(membership.user, application).update?
  end

  test "rejects an organization member without OAuth application permission" do
    membership = create(:organization_membership, :viewer)
    application = create(:oauth_application, owner: membership.organization)

    assert_not Pundit.policy!(membership.user, application).update?
  end
end
