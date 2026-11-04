# frozen_string_literal: true

class ProjectBeadsSource < ApplicationRecord
  include PublicIdGenerator

  belongs_to :project
  belongs_to :oauth_application
  belongs_to :current_snapshot, class_name: "ProjectBeadsSnapshot", optional: true
  before_destroy :clear_current_snapshot_reference
  has_many :snapshots, class_name: "ProjectBeadsSnapshot", dependent: :destroy

  validates :source_project_id, presence: true, length: { maximum: 255 }
  validates :repository_display_name, presence: true, length: { maximum: 255 }
  validates :project_id, uniqueness: true
  validate :connector_belongs_to_project_organization
  validate :connector_is_attached
  validate :current_snapshot_belongs_to_source

  def connector_attached?
    oauth_application.kept? && project.kept_project_memberships.exists?(oauth_application: oauth_application)
  end

  def verified?
    verified_at.present?
  end

  def roster_entries
    applications = project.kept_oauth_applications.kept.where(agent_capable: true).to_a
    applications << oauth_application if connector_attached? && applications.exclude?(oauth_application)
    applications.map do |application|
      {
        application: application,
        roles: [application.agent_capable? ? "Agent" : nil, application == oauth_application ? "Beads publisher" : nil].compact,
      }
    end
  end

  private

  def clear_current_snapshot_reference
    update_column(:current_snapshot_id, nil) if current_snapshot_id
  end

  def connector_belongs_to_project_organization
    errors.add(:oauth_application, "must belong to the project organization") unless oauth_application&.owner == project&.organization
  end

  def connector_is_attached
    errors.add(:oauth_application, "must have a kept project attachment") unless project && oauth_application && connector_attached?
  end

  def current_snapshot_belongs_to_source
    return unless current_snapshot && current_snapshot.project_beads_source_id != id

    errors.add(:current_snapshot, "must belong to this source")
  end
end
