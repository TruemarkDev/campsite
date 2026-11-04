# frozen_string_literal: true

module McpTools
  class RemoveProjectPin < McpTool
    tool_name "remove_project_pin"
    description "Remove a pin from a project. Requires write_project and project pin-removal permission."
    input_schema(org_scoped_schema(
      properties: { project_id: { type: "string" }, pin_id: { type: "string" } },
      required: ["project_id", "pin_id"],
    ))

    private

    def execute
      require_scope!("write_project")
      actor, organization, member = organization_context!
      project = organization.projects.find_by!(public_id: input[:project_id])
      authorize!(actor, project, :remove_pin?)
      pin = project.pins.find_by!(public_id: input[:pin_id])
      pin.discard_by_actor(member)
      data_response({ removed: true, pin_id: pin.public_id, project_id: project.public_id })
    end
  end
end
