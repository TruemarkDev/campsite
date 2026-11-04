# frozen_string_literal: true

require "digest"
require "securerandom"

class ProjectBeadsPairingChallenge < ApplicationRecord
  TTL = 10.minutes

  belongs_to :project
  belongs_to :oauth_application
  belongs_to :organization_membership

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validate :connector_belongs_to_project_organization
  validate :connector_is_attached

  class << self
    def issue!(project:, oauth_application:, organization_membership:)
      token = SecureRandom.urlsafe_base64(32)
      challenge = create!(
        project: project,
        oauth_application: oauth_application,
        organization_membership: organization_membership,
        token_digest: digest(token),
        expires_at: TTL.from_now,
      )
      [challenge, token]
    end

    def consume!(token:, oauth_application:, source_project_id:, repository_display_name:)
      transaction do
        challenge = lock.find_by!(token_digest: digest(token))
        raise ActiveRecord::RecordNotFound if challenge.consumed_at? || challenge.expires_at <= Time.current
        raise ActiveRecord::RecordNotFound unless challenge.oauth_application == oauth_application

        policy = ProjectPolicy.new(ApiActor.new(user: challenge.organization_membership.user), challenge.project)
        raise Pundit::NotAuthorizedError unless policy.manage_beads_source?
        raise ActiveRecord::RecordInvalid, challenge unless challenge.project.kept_project_memberships.exists?(oauth_application: oauth_application)

        source = challenge.project.project_beads_source || challenge.project.build_project_beads_source
        source.assign_attributes(
          oauth_application: oauth_application,
          source_project_id: source_project_id,
          repository_display_name: repository_display_name,
          verified_at: Time.current,
          current_snapshot: nil,
          last_successful_collection_at: nil,
          last_successful_ingest_at: nil,
        )
        source.save!
        source.snapshots.where.not(id: source.current_snapshot_id).delete_all
        challenge.update!(consumed_at: Time.current)
        source
      end
    end

    private

    def digest(token)
      Digest::SHA256.hexdigest(token.to_s)
    end
  end

  private

  def connector_belongs_to_project_organization
    errors.add(:oauth_application, "must belong to the project organization") unless oauth_application&.owner == project&.organization
  end

  def connector_is_attached
    errors.add(:oauth_application, "must have a kept project attachment") unless project&.kept_project_memberships&.exists?(oauth_application: oauth_application)
  end
end
