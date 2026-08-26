# frozen_string_literal: true

class CallRoomPolicy < ApplicationPolicy
  def show?
    no_subject? || @record.personal? || subject_member?
  end

  def create_invitation?
    show?
  end

  private

  def no_subject?
    !@record.subject
  end

  def subject_member?
    return false unless @record.subject.respond_to?(:memberships)
    return false unless user

    @record.subject.memberships.exists?(organization_membership: user.organization_memberships)
  end
end
