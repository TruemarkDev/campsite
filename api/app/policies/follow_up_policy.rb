# frozen_string_literal: true

class FollowUpPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope
    end
  end

  def update?
    owner?
  end

  def destroy?
    owner?
  end

  private

  def owner?
    user&.organization_memberships&.exists?(id: @record.organization_membership_id) || false
  end
end
