# frozen_string_literal: true

module McpTools
  # Creates a project under the connected user's membership. Requires the
  # `write_project` scope and runs the same authorization as the REST API.
  # Mirrors Api::V1::ProjectsController#create (safe subset: name, description,
  # private only — no slack, members, chat_format, or onboarding paths).
  class CreateProject < McpTool
    tool_name "create_project"
    description "Create a new project in an organization as the connected user. " \
      "Requires the write_project scope."
    input_schema(org_scoped_schema(
      properties: {
        name: { type: "string", description: "The project name." },
        description: { type: "string", description: "Optional project description." },
        private: { type: "boolean", description: "Create as a private project." },
      },
      required: ["name"],
    ))

    private

    def execute
      require_scope!("write_project")
      actor, organization, member = organization_context!
      authorize!(actor, organization, :create_project?)

      project = organization.projects.build(
        creator: member,
        name: input[:name],
        description: input[:description],
      )
      project.private = true if input[:private]

      if project.save
        data_response(serialize(ProjectSerializer, project, organization: organization, member: member))
      else
        error(project.errors.full_messages.to_sentence)
      end
    end
  end
end
