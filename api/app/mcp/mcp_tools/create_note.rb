# frozen_string_literal: true

module McpTools
  # Creates a note under the connected user's membership. Requires the `write_note`
  # scope and runs the same validations as the REST API. Mirrors
  # Api::V1::NotesController#create.
  class CreateNote < McpTool
    tool_name "create_note"
    description "Create a new note in an organization (optionally attached to a project) as the connected user. " \
      "To @mention a member, put `<@member_public_id>` in description_html (get ids from list_members). " \
      "Requires the write_note scope."
    input_schema(org_scoped_schema(
      properties: {
        title: { type: "string", description: "The note title." },
        description_html: { type: "string", description: "Note body as HTML; use `<@member_public_id>` to mention." },
        project_id: { type: "string", description: "Optional project public id." },
      },
      required: ["title"],
    ))

    private

    def execute
      require_scope!("write_note")
      actor, organization, member = organization_context!
      authorize!(actor, organization, :create_note?)

      project = organization.projects.find_by!(public_id: input[:project_id]) if input[:project_id].present?
      permission = project ? :view : :none

      note = member.notes.create!(
        title: input[:title],
        description_html: enrich_mentions(input[:description_html].to_s),
        project: project,
        project_permission: permission,
      )

      if note.errors.empty?
        data_response(serialize(NoteSerializer, note, organization: organization, member: member))
      else
        error("Could not create note: #{note.errors.full_messages.to_sentence}")
      end
    end
  end
end
