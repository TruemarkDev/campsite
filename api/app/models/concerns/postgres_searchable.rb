# frozen_string_literal: true

module PostgresSearchable
  extend ActiveSupport::Concern

  SEARCH_ATTRIBUTES = %w[id title generated_title description_html summary member_id room_id organization_id project_id discarded_at created_at].freeze

  included do
    after_save :refresh_search_document, if: :search_document_changed?
    after_destroy :remove_search_document
  end

  def search_document_changed?
    saved_changes.keys.intersect?(SEARCH_ATTRIBUTES)
  end

  def refresh_search_document
    return unless persisted? && !destroyed?

    self.class.transaction do
      source = self.class.lock.find_by(id: id)
      next unless source

      data = source.search_data
      SearchDocument.upsert({
        resource_type: self.class.name,
        resource_id: id,
        organization_id: data.fetch(:organization_id),
        fields: data,
        title: data[:title].to_s,
        content: data.slice(:description, :comments_content, :user_name, :user_username, :project_name, :summary, :transcription).values.flatten.compact.join(" "),
        resource_created_at: created_at,
      }, unique_by: [:resource_type, :resource_id], on_duplicate: SearchDocument::CONFLICT_UPDATE)
    end
  end

  def remove_search_document
    SearchDocument.where(resource_type: self.class.name, resource_id: id).delete_all
  end
end
