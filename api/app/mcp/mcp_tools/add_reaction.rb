# frozen_string_literal: true

module McpTools
  # Adds an emoji reaction to a post or comment as the connected user. Requires the
  # `write_post` scope and the same create_reaction? authorization as the REST API.
  class AddReaction < McpTool
    tool_name "add_reaction"
    description "Add an emoji reaction to a post or comment as the connected user. " \
      "Provide either a unicode emoji in `content` or a custom reaction id. Requires the write_post scope."
    input_schema(org_scoped_schema(
      properties: {
        subject_type: { type: "string", enum: ["post", "comment"], description: "Whether to react to a 'post' or a 'comment'." },
        subject_id: { type: "string", description: "The public id of the post or comment to react to." },
        content: { type: "string", description: "A unicode emoji to react with (e.g. \"👍\")." },
        custom_content_id: { type: "string", description: "The public id of a custom reaction to use instead of a unicode emoji." },
      },
      required: ["subject_type", "subject_id"],
    ))

    private

    def execute
      require_scope!("write_post")
      actor, organization, member = organization_context!

      subject = load_subject(organization)
      authorize!(actor, subject, :create_reaction?)

      if input[:content].blank? && input[:custom_content_id].blank?
        raise ToolError, "Provide either content (an emoji) or custom_content_id."
      end

      custom = input[:custom_content_id].present? ? CustomReaction.find_by(public_id: input[:custom_content_id]) : nil
      reaction = subject.reactions.create(content: input[:content], custom_content: custom, member: member)

      if reaction.errors.empty?
        data_response(serialize(ReactionSerializer, reaction, organization: organization, member: member))
      else
        error("Could not add reaction: #{reaction.errors.full_messages.to_sentence}")
      end
    end

    def load_subject(organization)
      case input[:subject_type]
      when "post"
        organization.kept_posts.find_by!(public_id: input[:subject_id])
      when "comment"
        Comment.kept.joins(:post).where(posts: { organization_id: organization.id }).find_by!(public_id: input[:subject_id])
      else
        raise ToolError, "subject_type must be 'post' or 'comment'."
      end
    end
  end
end
