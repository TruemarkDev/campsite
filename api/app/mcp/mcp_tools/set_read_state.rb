# frozen_string_literal: true

module McpTools
  class SetReadState < McpTool
    tool_name "set_read_state"
    description "Mark an accessible project or message thread read or unread for yourself."
    input_schema(org_scoped_schema(
      properties: {
        subject_type: { type: "string", enum: ["project", "thread"] },
        subject_id: { type: "string" },
        read: { type: "boolean" },
      },
      required: ["subject_type", "subject_id", "read"],
    ))

    private

    def execute
      actor, organization, member = organization_context!
      subject = if input[:subject_type] == "project"
        organization.projects.eager_load(:views).find_by!(public_id: input[:subject_id])
      else
        member.message_threads.find_by!(public_id: input[:subject_id])
      end
      authorize!(actor, subject, input[:read] ? :create_read? : :mark_unread?)
      input[:read] ? subject.mark_read(member) : subject.mark_unread(member)
      data_response({ subject_type: input[:subject_type], subject_id: subject.public_id, read: input[:read] })
    end
  end
end
