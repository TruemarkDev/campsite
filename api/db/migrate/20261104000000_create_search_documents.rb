# frozen_string_literal: true

class CreateSearchDocuments < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"
    # Derived data has no independent lifecycle; source timestamps are stored below.
    create_table :search_documents do |t| # rubocop:disable Rails/CreateTableWithTimestamps
      t.string :resource_type, null: false
      t.bigint :resource_id, null: false
      t.bigint :organization_id, null: false
      t.jsonb :fields, null: false, default: {}
      t.text :title, null: false, default: ""
      t.text :content, null: false, default: ""
      t.datetime :resource_created_at, null: false
      t.virtual :title_vector, type: :tsvector, as: "to_tsvector('simple', title)", stored: true
      t.virtual :content_vector, type: :tsvector, as: "to_tsvector('simple', content)", stored: true
    end
    add_index :search_documents, [:resource_type, :resource_id], unique: true
    add_index :search_documents, [:organization_id, :resource_type]
    add_index :search_documents, :title_vector, using: :gin
    add_index :search_documents, :content_vector, using: :gin
    add_index :search_documents, :title, using: :gin, opclass: :gin_trgm_ops
    add_index :search_documents, :content, using: :gin, opclass: :gin_trgm_ops
  end
end
