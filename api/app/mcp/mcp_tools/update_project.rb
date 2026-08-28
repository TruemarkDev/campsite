# frozen_string_literal: true

module McpTools
  class UpdateProject < McpTool
    tool_name "update_project"
    description "Update a project's name or description. Requires write_project and project update permission."
    input_schema(org_scoped_schema(
      properties: { project_id: { type: "string" }, name: { type: "string" }, description: { type: "string" } },
      required: ["project_id"],
    ))

    private

    def execute
      require_scope!("write_project")
      actor, organization, member = organization_context!
      project = organization.projects.serializer_includes.find_by!(public_id: input[:project_id])
      authorize!(actor, project, :update?)
      raise ToolError, "Provide name or description." unless input.key?(:name) || input.key?(:description)

      project.name = input[:name] if input.key?(:name)
      project.description = input[:description] if input.key?(:description)
      project.message_thread.title = input[:name] if input.key?(:name) && project.message_thread
      Project.transaction do
        project.save!
        project.message_thread&.save! if project.message_thread&.changed?
      end
      data_response(serialize(ProjectSerializer, project, organization: organization, member: member))
    end
  end
end
