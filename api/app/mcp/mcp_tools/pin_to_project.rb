# frozen_string_literal: true

module McpTools
  class PinToProject < McpTool
    tool_name "pin_to_project"
    description "Pin a post or project note in its project. Requires write_project."
    input_schema(org_scoped_schema(
      properties: { subject_type: { type: "string", enum: ["post", "note"] }, subject_id: { type: "string" } },
      required: ["subject_type", "subject_id"],
    ))

    private

    def execute
      require_scope!("write_project")
      actor, organization, member = organization_context!
      subject = input[:subject_type] == "post" ?
        organization.kept_posts.find_by!(public_id: input[:subject_id]) :
        organization.notes.kept.find_by!(public_id: input[:subject_id])
      raise ToolError, "The subject is not in a project." unless subject.project

      authorize!(actor, subject, :create_pin?)
      pin = subject.project.pins.create_or_find_by(subject: subject, pinner: member)
      pin.undiscard if pin.discarded?
      data_response({ pin_id: pin.public_id, project_id: subject.project.public_id, subject_id: subject.public_id })
    end
  end
end
