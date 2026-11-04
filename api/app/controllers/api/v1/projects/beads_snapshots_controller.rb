# frozen_string_literal: true

module Api
  module V1
    module Projects
      class BeadsSnapshotsController < BeadsPublisherBaseController
        extend Apigen::Controller

        rescue_from ProjectBeadsSnapshotSchema::Invalid, with: :render_invalid_snapshot

        response model: ProjectBeadsSnapshotSerializer, code: 200
        def create
          source = current_project.project_beads_source
          raise ActiveRecord::RecordNotFound unless source&.verified? && !current_project.archived?
          raise Pundit::NotAuthorizedError unless source.oauth_application == current_oauth_application && source.connector_attached?

          authorize(current_project, :read_beads_board?)
          snapshot = ProjectBeadsSnapshot.ingest!(source: source, attributes: request.request_parameters.except("beads_snapshot"))
          render(json: ProjectBeadsSnapshotSerializer.render_as_hash(snapshot))
        end

        private

        def render_invalid_snapshot(error)
          render_error(status: :unprocessable_entity, code: "invalid_beads_snapshot", message: error.message)
        end
      end
    end
  end
end
