# frozen_string_literal: true

class DataExportResourceJob < BaseJob
  sidekiq_options queue: "background", retry: 3

  sidekiq_retries_exhausted do |msg|
    export_resource_id = msg["args"].first
    export_resource = DataExportResource.find_by(id: export_resource_id)
    next unless export_resource

    export_resource.update!(status: :error, completed_at: Time.current)
    export_resource.data_export.check_completed
  end

  def perform(export_resource_id)
    export_resource = DataExportResource.eager_load(:data_export).find(export_resource_id)
    export_resource.perform
  end
end
