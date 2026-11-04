# frozen_string_literal: true

class OauthApplicationPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope
    end
  end

  def show?
    update?
  end

  def update?
    confirmed_user? && org_member? && organization_membership.role_has_permission?(resource: Role::OAUTH_APPLICATION_RESOURCE, permission: Role::UPDATE_ANY_ACTION)
  end

  def destroy?
    confirmed_user? && org_member? && organization_membership.role_has_permission?(resource: Role::OAUTH_APPLICATION_RESOURCE, permission: Role::DESTROY_ANY_ACTION)
  end

  def renew_secret?
    update?
  end

  private

  def org_member?
    organization_membership.present?
  end

  def organization_membership
    return @organization_membership if defined?(@organization_membership)

    return unless @record.owner_type == Organization.polymorphic_name && @user

    @organization_membership = @record.owner.kept_memberships.find_by(user_id: @user.id)
  end
end
