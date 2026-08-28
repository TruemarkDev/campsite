# frozen_string_literal: true

class BeadsCardSerializer < ApiSerializer
  api_field :id
  api_field :title
  api_field :status
  api_field :board_state, enum: ProjectBeadsSnapshotSchema::BOARD_STATES
  api_field :priority, type: :number
  api_field :issue_type
  api_field :assignee, nullable: true
  api_field :owner, nullable: true
  api_field :labels, is_array: true
  api_field :parent_id, nullable: true
  api_field :dependencies, type: :object, is_array: true, properties: {
    id: { type: :string },
    type: { type: :string },
  }
  api_field :created_at
  api_field :updated_at
  api_field :closed_at, nullable: true
end
