# frozen_string_literal: true

namespace :search do
  desc "Rebuild PostgreSQL search documents from canonical records (idempotent)"
  task rebuild: :environment do
    [Post, Note, Call].each do |model|
      model.find_each(&:refresh_search_document)
      SearchDocument.where(resource_type: model.name).where.not(resource_id: model.select(:id)).delete_all
      puts "#{model.name}: #{SearchDocument.where(resource_type: model.name).count} search documents"
    end
  end
end
