# frozen_string_literal: true

module Api
  module V1
    module Notes
      class SyncStatesController < BaseController
        extend Apigen::Controller

        response model: NoteSyncSerializer, code: 200
        def show
          note = current_organization.notes.kept.find_by!(public_id: params[:note_id])
          authorize(note, :show?)
          render_json(NoteSyncSerializer, note)
        end

        response model: NoteSyncSerializer, code: 200
        request_params do
          {
            description_html: { type: :string },
            description_state: { type: :string },
            description_schema_version: { type: :integer },
            initialize: { type: :boolean, required: false },
          }
        end
        def update
          note = current_organization.notes.find_by!(public_id: params[:note_id])

          authorize(note, :sync?)

          note.with_lock do
            # HTML-to-Yjs conversion creates a new CRDT lineage. Only the first
            # cold loader may establish it; every concurrent loader must use
            # the already-persisted state returned here.
            if params[:initialize]
              if note.description_state.blank?
                if !params[:description_schema_version].nil? && params[:description_schema_version] < note.description_schema_version
                  render_unprocessable_entity(note) && return
                end

                note.update_columns(
                  description_html: params[:description_html],
                  description_state: params[:description_state],
                  description_schema_version: params[:description_schema_version],
                )
              end

              render_json(NoteSyncSerializer, note) && return
            end

            if !params[:description_schema_version].nil? && params[:description_schema_version] < note.description_schema_version
              render_unprocessable_entity(note) && return
            end

            note.event_actor = current_organization_membership
            note.description_html = params[:description_html]
            note.description_state = params[:description_state]
            note.description_schema_version = params[:description_schema_version]

            render_unprocessable_entity(note) && return unless note.save
          end

          render_json(NoteSyncSerializer, note)
        end
      end
    end
  end
end
