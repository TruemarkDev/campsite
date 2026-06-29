# frozen_string_literal: true

module McpTools
  # Reads a single note by its public id. Mirrors Api::V1::NotesController#show.
  class ReadNote < McpTool
    tool_name "read_note"
    description "Read a single note by its public id, including its HTML content."
    input_schema(org_scoped_schema(
      properties: {
        note_id: { type: "string", description: "The public id of the note to read." },
      },
      required: ["note_id"],
    ))

    private

    def execute
      actor, organization, member = organization_context!

      note = organization.notes.kept.serializer_preload.find_by!(public_id: input[:note_id])
      authorize!(actor, note, :show?)

      data = serialize(NoteSerializer, note, organization: organization, member: member)
      data_response(data)
    end
  end
end
