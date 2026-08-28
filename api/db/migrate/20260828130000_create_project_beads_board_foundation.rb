# frozen_string_literal: true

class CreateProjectBeadsBoardFoundation < ActiveRecord::Migration[7.2]
  def change
    add_column :oauth_applications, :agent_capable, :boolean, null: false, default: false

    create_table :project_beads_sources, id: { type: :bigint, unsigned: true } do |t|
      t.string :public_id, null: false
      t.references :project, null: false, unsigned: true, foreign_key: { on_delete: :cascade }, index: false
      t.references :oauth_application, null: false, foreign_key: true
      t.string :source_project_id, null: false
      t.string :repository_display_name, null: false
      t.datetime :verified_at, null: false
      t.bigint :current_snapshot_id, unsigned: true
      t.datetime :last_successful_collection_at
      t.datetime :last_successful_ingest_at
      t.timestamps

      t.index :public_id, unique: true
      t.index :project_id, unique: true
      t.index [:oauth_application_id, :source_project_id], name: "index_project_beads_sources_on_connector_and_source"
    end

    create_table :project_beads_snapshots, id: { type: :bigint, unsigned: true } do |t|
      t.references :project_beads_source, null: false, unsigned: true, foreign_key: { on_delete: :cascade }, index: { name: "index_beads_snapshots_on_source_id" }
      t.integer :schema_version, null: false
      t.string :beads_version, null: false
      t.string :beads_schema_version
      t.string :branch, null: false
      t.string :revision, null: false
      t.datetime :collected_at, null: false
      t.datetime :ingested_at, null: false
      t.string :digest, null: false, limit: 64
      t.json :payload, null: false
      t.timestamps

      t.index [:project_beads_source_id, :digest], unique: true, name: "index_beads_snapshots_on_source_and_digest"
      t.index [:id, :project_beads_source_id], unique: true, name: "index_beads_snapshots_on_id_and_source_id"
    end

    add_index :project_beads_sources, [:current_snapshot_id, :id], name: "index_beads_sources_on_current_snapshot_and_id"
    safety_assured do
      # Both tables are created empty in this migration, so adding the circular
      # current-pointer constraint cannot block application writes.
      add_foreign_key :project_beads_sources,
        :project_beads_snapshots,
        column: [:current_snapshot_id, :id],
        primary_key: [:id, :project_beads_source_id],
        name: "fk_beads_sources_current_snapshot"
    end

    create_table :project_beads_pairing_challenges, id: { type: :bigint, unsigned: true } do |t|
      t.references :project, null: false, unsigned: true, foreign_key: { on_delete: :cascade }
      t.references :oauth_application, null: false, foreign_key: true
      t.references :organization_membership, null: false, unsigned: true, foreign_key: true, index: { name: "index_beads_pairings_on_initiator_id" }
      t.string :token_digest, null: false, limit: 64
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps

      t.index :token_digest, unique: true
      t.index [:project_id, :consumed_at], name: "index_beads_pairings_on_project_and_consumed_at"
    end
  end
end
