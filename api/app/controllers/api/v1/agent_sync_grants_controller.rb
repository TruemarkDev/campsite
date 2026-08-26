# frozen_string_literal: true

module Api
  module V1
    class AgentSyncGrantsController < ActionController::API
      extend Apigen::Controller

      before_action :authenticate_grant!

      response code: 200 do
        {
          grant_id: { type: :string },
          note_id: { type: :string },
          organization: { type: :string },
          actor_id: { type: :string },
          actor_name: { type: :string },
          invoked_by: { type: :string },
          expires_at: { type: :string },
        }
      end
      request_params do
        { note_id: { type: :string } }
      end
      def verify
        render(json: grant_payload, status: :ok)
      end

      response code: 200 do
        {
          description_html: { type: :string },
          description_state: { type: :string, required: false },
          description_schema_version: { type: :integer },
        }
      end
      def show_state
        render(
          json: {
            description_html: @grant.note.description_html.to_s,
            description_state: @grant.note.description_state,
            description_schema_version: @grant.note.description_schema_version,
          },
          status: :ok,
        )
      end

      response code: 200 do
        {
          description_html: { type: :string },
          description_state: { type: :string, required: false },
          description_schema_version: { type: :integer },
        }
      end
      request_params do
        {
          description_html: { type: :string },
          description_state: { type: :string },
          description_schema_version: { type: :integer },
          initialize: { type: :boolean, required: false },
        }
      end
      def update_state
        note = @grant.note
        version = params[:description_schema_version].to_i

        note.with_lock do
          return render_state(note) if params[:initialize] && note.description_state.present?
          return render(status: :unprocessable_content, json: { code: "stale_schema" }) if version < note.description_schema_version

          note.event_actor = @grant.organization_membership
          unless note.update(
            description_html: params[:description_html],
            description_state: params[:description_state],
            description_schema_version: version,
          )
            return render(status: :unprocessable_content, json: { code: "invalid_sync_state", errors: note.errors.full_messages })
          end
        end

        render_state(note)
      end

      response code: 201
      request_params do
        {
          batch_id: { type: :string },
          instruction: { type: :string, required: false },
        }
      end
      def create_attribution
        return render(status: :unprocessable_content, json: { code: "invalid_attribution" }) if params[:batch_id].blank?

        @grant.note.timeline_events.create!(
          action: :note_suggestion_proposed,
          actor: @grant.organization_membership,
          metadata: {
            batch_id: params[:batch_id],
            actor_name: @grant.actor_name,
            instruction: params[:instruction]&.first(500),
          }.compact,
        )
        render(json: {}, status: :created)
      end

      private

      def authenticate_grant!
        note_id = params[:note_id]
        authorization = request.authorization.to_s
        return render_unauthorized unless authorization.start_with?("Bearer ")

        token = authorization.delete_prefix("Bearer ")
        return render_unauthorized if token.blank?

        @grant = AgentSyncGrant.authenticate(token: token, note_public_id: note_id)
        render_unauthorized unless @grant
      end

      def render_unauthorized
        render(status: :unauthorized, json: { code: "invalid_agent_sync_grant" })
      end

      def render_state(note)
        render(
          json: {
            description_html: note.description_html.to_s,
            description_state: note.description_state,
            description_schema_version: note.description_schema_version,
          },
          status: :ok,
        )
      end

      def grant_payload
        {
          grant_id: @grant.public_id,
          note_id: @grant.note.public_id,
          organization: @grant.note.organization.slug,
          actor_id: @grant.actor_id,
          actor_name: @grant.actor_name,
          invoked_by: @grant.organization_membership.public_id,
          expires_at: @grant.expires_at.iso8601,
        }
      end
    end
  end
end
