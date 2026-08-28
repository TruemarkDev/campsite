# frozen_string_literal: true

class TagPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope
    end
  end

  def show?
    org_member?
  end

  def list_posts?
    org_member?
  end

  def update?
    confirmed_user? && org_member?
  end

  def destroy?
    confirmed_user? && org_member? &&
      organization_membership.role_has_permission?(resource: Role::TAG_RESOURCE, permission: Role::DESTROY_ANY_ACTION)
  end

  def create_tag?
    confirmed_user? && org_member?
  end

  def create_favorite?
    confirmed_user? && org_member?
  end

  def remove_favorite?
    confirmed_user? && org_member?
  end

  private

  def org_member?
    organization_membership.present?
  end

  def organization_membership
    return @organization_membership if defined?(@organization_membership)

    @organization_membership = @record.organization.kept_memberships.find_by(user_id: @user&.id)
  end
end
