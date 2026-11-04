# frozen_string_literal: true

module Api
  module V1
    module Notes
      class SuggestionResolutionsController < BaseController
        extend Apigen::Controller

        response code: 201
        request_params do
          {
            batch_id: { type: :string },
            resolution: { type: :string, enum: ["accept", "reject"] },
          }
        end
        def create
          unless params[:batch_id].present? && ["accept", "reject"].include?(params[:resolution])
            return render_error(status: :unprocessable_content, code: "invalid_resolution", message: "Invalid suggestion resolution")
          end

          note = current_organization.notes.kept.find_by!(public_id: params[:note_id])
          authorize(note, :update?)

          note.timeline_events.create!(
            action: :note_suggestion_resolved,
            actor: current_organization_membership,
            metadata: {
              batch_id: params[:batch_id],
              resolution: params[:resolution],
            },
          )
          render(json: {}, status: :created)
        end
      end
    end
  end
end
