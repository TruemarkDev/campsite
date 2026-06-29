# frozen_string_literal: true

module McpTools
  # Lists notes in an organization the user can see. Mirrors
  # Api::V1::NotesController#index.
  class ListNotes < McpTool
    tool_name "list_notes"
    description "List notes in an organization that the user can access, most recent activity first."
    input_schema(org_scoped_schema(paginated: true))

    private

    def execute
      actor, organization, member = organization_context!
      authorize!(actor, organization, :list_notes?)

      scope = policy_scope(actor, organization.notes.kept.serializer_preload)
      page = paginate(scope, order: { last_activity_at: :desc, id: :desc })
      data = serialize(NotePageSerializer, page, organization: organization, member: member)
      data_response(data)
    end
  end
end
