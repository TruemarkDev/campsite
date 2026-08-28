# frozen_string_literal: true

module McpTools
  class ArchiveProject < McpTool
    tool_name "archive_project"
    description "Archive a project. Requires write_project and archive permission."
    input_schema(org_scoped_schema(properties: { project_id: { type: "string" } }, required: ["project_id"]))

    private

    def execute
      require_scope!("write_project")
      actor, organization, member = organization_context!
      project = organization.projects.serializer_includes.find_by!(public_id: input[:project_id])
      authorize!(actor, project, :archive?)
      project.archive!(member) unless project.archived?
      data_response(serialize(ProjectSerializer, project, organization: organization, member: member))
    end
  end
end
