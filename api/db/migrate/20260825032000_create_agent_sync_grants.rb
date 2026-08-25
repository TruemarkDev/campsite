# frozen_string_literal: true

class CreateAgentSyncGrants < ActiveRecord::Migration[8.1]
  def change
    create_table(:agent_sync_grants) do |t|
      t.string(:public_id, limit: 12, null: false, index: { unique: true })
      t.references(:note, null: false, unsigned: true)
      t.references(:organization_membership, null: false, unsigned: true)
      t.string(:actor_id, null: false)
      t.string(:actor_name, null: false)
      t.string(:token_digest, null: false, index: { unique: true })
      t.json(:scopes, null: false)
      t.datetime(:expires_at, null: false)
      t.datetime(:revoked_at)
      t.timestamps
    end
  end
end
