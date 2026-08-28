# frozen_string_literal: true

module McpTools
  class ReadProject < McpTool
    tool_name "read_project"
    description "Read one accessible project by public id."
    input_schema(org_scoped_schema(properties: { project_id: { type: "string" } }, required: ["project_id"]))

    private

    def execute
      actor, organization, member = organization_context!
      project = organization.projects.serializer_includes.find_by!(public_id: input[:project_id])
      authorize!(actor, project, :show?)
      data_response(serialize(ProjectSerializer, project, organization: organization, member: member))
    end
  end
end
