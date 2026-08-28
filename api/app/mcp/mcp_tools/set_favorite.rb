# frozen_string_literal: true

module McpTools
  class SetFavorite < McpTool
    TYPES = ["post", "note", "project", "thread"].freeze

    tool_name "set_favorite"
    description "Favorite or unfavorite an accessible post, note, project, or message thread for yourself."
    input_schema(org_scoped_schema(
      properties: {
        subject_type: { type: "string", enum: TYPES },
        subject_id: { type: "string" },
        favorite: { type: "boolean" },
      },
      required: ["subject_type", "subject_id", "favorite"],
    ))

    private

    def execute
      actor, organization, member = organization_context!
      subject = load_subject(organization, member)
      query = input[:favorite] ? :create_favorite? : :remove_favorite?
      authorize!(actor, subject, query)

      favorite = subject.favorites.find_by(organization_membership: member)
      if input[:favorite]
        favorite ||= subject.favorites.create!(organization_membership: member)
      else
        favorite&.destroy!
      end
      data_response({ subject_type: input[:subject_type], subject_id: subject.public_id, favorite: input[:favorite], favorite_id: favorite&.public_id })
    end

    def load_subject(organization, member)
      case input[:subject_type]
      when "post" then organization.kept_posts.find_by!(public_id: input[:subject_id])
      when "note" then organization.notes.kept.find_by!(public_id: input[:subject_id])
      when "project" then organization.projects.find_by!(public_id: input[:subject_id])
      when "thread" then member.message_threads.find_by!(public_id: input[:subject_id])
      else raise ToolError, "Unsupported subject_type."
      end
    end
  end
end
