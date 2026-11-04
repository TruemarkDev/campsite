# frozen_string_literal: true

module Api
  module V1
    module Notes
      class AgentSyncGrantsController < BaseController
        extend Apigen::Controller

        response code: 201 do
          {
            id: { type: :string },
            token: { type: :string },
            expires_at: { type: :string },
          }
        end
        request_params do
          {
            actor_id: { type: :string },
            actor_name: { type: :string },
            expires_in: { type: :integer, required: false },
          }
        end
        def create
          note = current_organization.notes.kept.find_by!(public_id: params[:note_id])
          authorize(note, :update?)
          return render_not_found unless feature_enabled?

          grant, token = AgentSyncGrant.issue!(
            note: note,
            organization_membership: current_organization_membership,
            actor_id: params[:actor_id],
            actor_name: params[:actor_name],
            expires_in: params[:expires_in] || AgentSyncGrant::MAX_LIFETIME,
          )

          render(
            json: { id: grant.public_id, token: token, expires_at: grant.expires_at.iso8601 },
            status: :created,
          )
        rescue ArgumentError => e
          render_error(status: :unprocessable_entity, code: "invalid_agent_sync_grant", message: e.message)
        end

        response code: 204
        def destroy
          note = current_organization.notes.kept.find_by!(public_id: params[:note_id])
          authorize(note, :update?)
          note.agent_sync_grants.find_by!(public_id: params[:id]).revoke!
          head(:no_content)
        end

        private

        def feature_enabled?
          Flipper.enabled?(:ai_note_editing, current_user) || Flipper.enabled?(:ai_note_editing, current_organization)
        end
      end
    end
  end
end
