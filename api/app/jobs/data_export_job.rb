# frozen_string_literal: true

class DataExportJob < BaseJob
  sidekiq_options queue: "background", retry: 3

  sidekiq_retries_exhausted do |msg|
    DataExport.find_by(id: msg["args"].first)&.fail!
  end

  def perform(export_id)
    export = DataExport.find(export_id)
    export.perform
  end
end
