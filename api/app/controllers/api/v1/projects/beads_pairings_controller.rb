# frozen_string_literal: true

module Api
  module V1
    module Projects
      class BeadsPairingsController < BaseController
        extend Apigen::Controller

        after_action :verify_authorized

        response model: ProjectBeadsPairingSerializer, code: 201
        request_params do
          { oauth_application_id: { type: :string } }
        end
        def create
          authorize(current_project, :manage_beads_source?)
          return render_not_found unless feature_enabled?

          application = current_organization.kept_oauth_applications.find_by!(public_id: params[:oauth_application_id])
          challenge, token = ProjectBeadsPairingChallenge.issue!(
            project: current_project,
            oauth_application: application,
            organization_membership: current_organization_membership,
          )
          render_json(ProjectBeadsPairingSerializer, { challenge: token, expires_at: challenge.expires_at }, status: :created)
        end

        private

        def feature_enabled?
          Flipper.enabled?(:channel_beads_board, current_organization)
        end
      end
    end
  end
end
