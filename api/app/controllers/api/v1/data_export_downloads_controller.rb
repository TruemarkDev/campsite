# frozen_string_literal: true

module Api
  module V1
    class DataExportDownloadsController < BaseController
      def show
        export = DataExport.completed.find_by!(public_id: params[:id])
        authorize(export, :download?)

        redirect_to(export.presigned_download_url, allow_other_host: true)
      end
    end
  end
end
