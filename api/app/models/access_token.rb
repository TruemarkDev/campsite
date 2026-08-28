# frozen_string_literal: true

class AccessToken < ApplicationRecord
  include ::Doorkeeper::Orm::ActiveRecord::Mixins::AccessToken

  self.table_name = "oauth_access_tokens"

  belongs_to :resource_owner, polymorphic: true

  after_create_commit :broadcast_stale

  # Doorkeeper otherwise keeps the previous refresh token usable during a
  # transition window when this table has a previous_refresh_token column.
  # Immediate revocation makes rotation single-use and serializes concurrent
  # refreshes under the gem's row lock.
  def self.refresh_token_revoked_on_use?
    false
  end

  def owned_by_organization?
    resource_owner_type == "Organization"
  end

  def owned_by_user?
    resource_owner_type == "User"
  end

  private

  def broadcast_stale
    if resource_owner&.respond_to?(:channel_name)
      PusherTriggerJob.perform_async(resource_owner.channel_name, "access-tokens-stale", nil.to_json)
    end
  end
end
