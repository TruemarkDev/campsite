# frozen_string_literal: true

module Api
  module V1
    module Projects
      class BeadsPublisherBaseController < Api::V2::BaseController
        before_action :require_feature_enabled

        private

        def current_project
          @current_project ||= current_organization.projects.find_by!(public_id: params[:project_id])
        end

        def require_feature_enabled
          render_error(status: :not_found, code: "not_found", message: "Not found") unless current_organization && Flipper.enabled?(:channel_beads_board, current_organization)
        end
      end
    end
  end
end
