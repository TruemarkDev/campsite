# frozen_string_literal: true

module Api
  module V1
    module Notes
      class AiEditsController < BaseController
        extend Apigen::Controller

        RATE_LIMIT = 10
        RATE_PERIOD = 1.minute

        response code: 200 do
          {
            batch_id: { type: :string },
            actor_id: { type: :string },
            actor_type: { type: :string, enum: ["ai"] },
            invoked_by: { type: :string },
            created_at: { type: :string },
            instruction: { type: :string },
            operations: {
              type: :object,
              is_array: true,
              properties: {
                type: { type: :string, enum: ["replace_range", "insert_at_cursor"] },
                text: { type: :string },
              },
            },
          }
        end
        request_params do
          {
            instruction: { type: :string },
            range: {
              type: :object,
              properties: {
                from: { type: :integer },
                to: { type: :integer },
              },
            },
            context: {
              type: :object,
              properties: {
                selected_text: { type: :string },
                before: { type: :string },
                after: { type: :string },
              },
            },
          }
        end
        def create
          note = current_organization.notes.kept.find_by!(public_id: params[:note_id])
          authorize(note, :update?)
          return render_not_found unless feature_enabled?
          return render_rate_limited unless within_rate_limit?

          range = params.require(:range).permit(:from, :to)
          context = params.require(:context).permit(:selected_text, :before, :after)
          validate_range!(range)

          text = NoteAiEditor.new(
            note: note,
            instruction: params[:instruction],
            selected_text: context[:selected_text],
            before: context[:before],
            after: context[:after],
          ).call

          payload = response_payload(text: text, selected_text: context[:selected_text])
          note.timeline_events.create!(
            action: :note_suggestion_proposed,
            actor: current_organization_membership,
            metadata: {
              batch_id: payload[:batch_id],
              actor_name: "Campsite AI",
              instruction: payload[:instruction].first(500),
            },
          )

          render(json: payload, status: :ok)
        rescue ActionController::ParameterMissing, ArgumentError => e
          render_error(status: :unprocessable_entity, code: "invalid_ai_edit", message: e.message)
        end

        private

        def feature_enabled?
          Flipper.enabled?(:ai_note_editing, current_user) || Flipper.enabled?(:ai_note_editing, current_organization)
        end

        def within_rate_limit?
          key = "ai-note-editing:#{current_organization_membership.id}:#{Time.current.to_i / RATE_PERIOD.to_i}"
          Rails.cache.increment(key, 1, expires_in: RATE_PERIOD) <= RATE_LIMIT
        end

        def render_rate_limited
          render_error(
            status: :too_many_requests,
            code: "ai_edit_rate_limited",
            message: "Too many AI edit requests. Try again in a minute.",
          )
        end

        def validate_range!(range)
          from = Integer(range[:from])
          to = Integer(range[:to])
          raise ArgumentError, "range is invalid" if from.negative? || to < from
        end

        def response_payload(text:, selected_text:)
          {
            batch_id: SecureRandom.uuid,
            actor_id: "campsite-ai",
            actor_type: "ai",
            invoked_by: current_organization_membership.public_id,
            created_at: Time.current.iso8601,
            instruction: params[:instruction].to_s.strip,
            operations: [
              {
                type: selected_text.present? ? "replace_range" : "insert_at_cursor",
                text: text,
              },
            ],
          }
        end
      end
    end
  end
end
