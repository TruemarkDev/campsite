# frozen_string_literal: true

class ProjectBeadsSnapshotSerializer < ApiSerializer
  api_field :schema_version, type: :number
  api_field :beads_version
  api_field :beads_schema_version, nullable: true
  api_field :branch
  api_field :revision
  api_field :collected_at
  api_field :ingested_at
  api_field :digest
  api_association :payload, name: :cards, blueprint: BeadsCardSerializer, is_array: true
end
