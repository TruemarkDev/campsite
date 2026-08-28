# frozen_string_literal: true

class ProjectBeadsSnapshot < ApplicationRecord
  belongs_to :project_beads_source

  validates :schema_version, inclusion: { in: [1] }
  validates :beads_version, :branch, :revision, :digest, presence: true
  validates :digest, uniqueness: { scope: :project_beads_source_id }, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :collected_at, :ingested_at, presence: true

  class << self
    def ingest!(source:, attributes:)
      normalized = ProjectBeadsSnapshotSchema.validate!(attributes, source: source)
      advanced = false

      snapshot = transaction do
        source.lock!
        existing = source.snapshots.find_by(digest: normalized.fetch("digest"))
        next existing if existing

        created = source.snapshots.create!(
          schema_version: normalized.fetch("schema_version"),
          beads_version: normalized.fetch("beads_version"),
          beads_schema_version: normalized["beads_schema_version"],
          branch: normalized.fetch("branch"),
          revision: normalized.fetch("revision"),
          collected_at: normalized.fetch("collected_at"),
          ingested_at: Time.current,
          digest: normalized.fetch("digest"),
          payload: normalized.fetch("issues"),
        )

        if source.current_snapshot.nil? || created.collected_at >= source.current_snapshot.collected_at
          source.update!(
            current_snapshot: created,
            last_successful_collection_at: created.collected_at,
            last_successful_ingest_at: created.ingested_at,
          )
          advanced = true
        end

        created
      end

      if advanced
        PusherTriggerJob.perform_async(
          source.project.organization.channel_name,
          "project-beads-board-stale",
          { project_id: source.project.public_id }.to_json,
        )
      end

      snapshot
    end
  end
end
