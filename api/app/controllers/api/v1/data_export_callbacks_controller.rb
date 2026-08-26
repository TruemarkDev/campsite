# frozen_string_literal: true

module Api
  module V1
    class DataExportCallbacksController < BaseController
      skip_before_action :require_authenticated_user, only: :update
      skip_before_action :require_org_two_factor_authentication, only: :update
      skip_before_action :require_authenticated_organization_membership, only: :update
      before_action :require_valid_callback_token, only: :update

      def update
        if current_data_export.complete(params[:zip_path])
          render_ok
        else
          head(:conflict)
        end
      rescue DataExport::InvalidZipPath
        render_error(status: :unprocessable_entity, code: :invalid_zip_path, message: "Invalid export path")
      end

      private

      def current_data_export
        @current_data_export ||= DataExport.find_by!(public_id: params[:id])
      end

      def require_valid_callback_token
        token = request.headers["X-Campsite-Export-Token"]
        head(:unauthorized) unless token.present? && current_data_export.valid_callback_token?(token)
      end
    end
  end
end
