# frozen_string_literal: true

module McpTools
  # Lists the projects (channels) in an organization the user can see. Mirrors
  # Api::V1::ProjectsController#index.
  class ListProjects < McpTool
    tool_name "list_projects"
    description "List the projects (channels) in an organization that the user can access."
    input_schema(org_scoped_schema(
      properties: {
        q: { type: "string", description: "Optional search query to filter projects by name." },
        archived: { type: "boolean", description: "When true, return archived projects instead of active ones." },
      },
      paginated: true,
    ))

    private

    def execute
      actor, organization, member = organization_context!
      authorize!(actor, organization, :list_projects?)

      projects = policy_scope(actor, organization.projects)
      projects = projects.search_by(input[:q]) if input[:q].present?
      projects = input[:archived] == true ? projects.archived : projects.not_archived

      page = paginate(projects.serializer_includes, order: { last_activity_at: :desc, id: :desc })
      data = serialize(ProjectPageSerializer, page, organization: organization, member: member)
      data_response(data)
    end
  end
end
