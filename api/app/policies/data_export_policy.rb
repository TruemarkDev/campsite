# frozen_string_literal: true

class DataExportPolicy < ApplicationPolicy
  def download?
    confirmed_user? && record.member.user == user
  end
end
