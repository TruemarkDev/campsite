# frozen_string_literal: true

module Api
  module V1
    module Projects
      class BeadsBoardsController < BaseController
        extend Apigen::Controller

        after_action :verify_authorized

        response model: ProjectBeadsBoardSerializer, code: 200
        def show
          authorize(current_project, :read_beads_board?)
          return render_not_found unless feature_enabled?

          source = current_project.project_beads_source
          return render_not_found unless source&.verified?

          render_json(ProjectBeadsBoardSerializer, source)
        end

        private

        def feature_enabled?
          Flipper.enabled?(:channel_beads_board, current_user) || Flipper.enabled?(:channel_beads_board, current_organization)
        end
      end
    end
  end
end
