# frozen_string_literal: true

module Api
  module V1
    module Projects
      class BeadsPairingCompletionsController < BeadsPublisherBaseController
        extend Apigen::Controller

        skip_after_action :verify_policy_scoped
        rescue_from ProjectBeadsSnapshotSchema::Invalid do |error|
          render_error(status: :unprocessable_entity, code: "invalid_beads_identity", message: error.message)
        end

        response model: ProjectBeadsBoardSerializer, code: 200
        request_params do
          {
            challenge: { type: :string },
            source_project_id: { type: :string },
            repository_display_name: { type: :string },
            beads_version: { type: :string },
            branch: { type: :string },
            revision: { type: :string },
          }
        end
        def create
          source = ProjectBeadsPairingChallenge.consume!(
            project: current_project,
            token: params[:challenge],
            oauth_application: current_oauth_application,
            source_project_id: params[:source_project_id],
            repository_display_name: params[:repository_display_name],
            beads_version: params[:beads_version],
            branch: params[:branch],
            revision: params[:revision],
          )
          authorize(source.project, :read_beads_board?)
          render(json: ProjectBeadsBoardSerializer.render_as_hash(source))
        end
      end
    end
  end
end
