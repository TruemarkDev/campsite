# frozen_string_literal: true

class ProjectBeadsBoardSerializer < ApiSerializer
  api_field :public_id, name: :source_id
  api_field :source_project_id
  api_field :repository_display_name
  api_field :verified_at
  api_field :last_successful_collection_at, nullable: true
  api_field :last_successful_ingest_at, nullable: true
  api_association :current_snapshot, blueprint: ProjectBeadsSnapshotSerializer, nullable: true
  api_association :roster_entries, name: :agents, blueprint: ChannelAgentSummarySerializer, is_array: true
end
