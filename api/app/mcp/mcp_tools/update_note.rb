# frozen_string_literal: true

module McpTools
  # Updates a note's title under the connected user's identity. Mirrors
  # Api::V1::NotesController#update (title only — the body is collaborative state
  # and is never touched here). Requires the `write_note` scope.
  class UpdateNote < McpTool
    tool_name "update_note"
    description "Update the title of an existing note as the connected user. " \
      "Only the title is changed; the note body is collaborative state and is left untouched. " \
      "Requires the write_note scope."
    input_schema(org_scoped_schema(
      properties: {
        note_id: { type: "string", description: "The public id of the note to update." },
        title: { type: "string", description: "The new note title." },
      },
      required: ["note_id", "title"],
    ))

    private

    def execute
      require_scope!("write_note")
      actor, organization, member = organization_context!

      note = organization.notes.kept.serializer_preload.find_by!(public_id: input[:note_id])
      authorize!(actor, note, :update?)

      note.title = input[:title]

      if note.save
        data_response(serialize(NoteSerializer, note, organization: organization, member: member))
      else
        error("Could not update note: #{note.errors.full_messages.to_sentence}")
      end
    end
  end
end
