# frozen_string_literal: true

module McpTools
  class RemoveNote < McpTool
    tool_name "remove_note"
    description "Discard a note the connected user may remove. Requires write_note."
    input_schema(org_scoped_schema(properties: { note_id: { type: "string" } }, required: ["note_id"]))

    private

    def execute
      require_scope!("write_note")
      actor, organization, member = organization_context!
      note = organization.notes.kept.find_by!(public_id: input[:note_id])
      authorize!(actor, note, :destroy?)
      note.discard_by_actor(member)
      data_response({ removed: true, note_id: note.public_id })
    end
  end
end
