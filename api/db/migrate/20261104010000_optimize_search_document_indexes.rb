# frozen_string_literal: true

class OptimizeSearchDocumentIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :search_documents, "(strip(content_vector)::text) gin_trgm_ops", using: :gin,
      name: "index_search_documents_on_content_lexemes", algorithm: :concurrently
    # Measured blank-query plans sort 20,000 tenant rows. Both equality keys
    # and both ordering keys are required for this bounded, deterministic scan.
    safety_assured do
      add_index :search_documents, [:organization_id, :resource_type, :resource_created_at, :resource_id],
        order: { resource_created_at: :desc, resource_id: :desc },
        where: "fields->>'discarded_at' IS NULL", name: "index_search_documents_on_active_browse", algorithm: :concurrently
    end
    # All four keys are equality predicates for author-filtered tenant searches.
    # Including discarded_at as an expression also gives ANALYZE its selectivity.
    safety_assured do
      add_index :search_documents, "organization_id, resource_type, (fields->>'discarded_at'), (fields->>'user_id')",
        name: "index_search_documents_on_author_filters", algorithm: :concurrently
    end
    remove_index :search_documents, name: "index_search_documents_on_content", algorithm: :concurrently
  end

  def down
    add_index :search_documents, :content, using: :gin, opclass: :gin_trgm_ops, algorithm: :concurrently
    remove_index :search_documents, name: "index_search_documents_on_author_filters", algorithm: :concurrently
    remove_index :search_documents, name: "index_search_documents_on_active_browse", algorithm: :concurrently
    remove_index :search_documents, name: "index_search_documents_on_content_lexemes", algorithm: :concurrently
  end
end
