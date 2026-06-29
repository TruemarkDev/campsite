# frozen_string_literal: true

module McpTools
  # Adds a comment to a post or a note as the connected user. Requires the
  # `write_post` scope and runs the same Comment::CreateComment service and
  # authorization as the REST API.
  class AddComment < McpTool
    tool_name "add_comment"
    description "Add a comment to a post or a note as the connected user. " \
      "To @mention a member, put `<@member_public_id>` in body_html (get ids from list_members). Requires the write_post scope."
    input_schema(org_scoped_schema(
      properties: {
        subject_type: { type: "string", enum: ["post", "note"], description: "Whether to comment on a 'post' or a 'note'." },
        subject_id: { type: "string", description: "The public id of the post or note to comment on." },
        body_html: { type: "string", description: "The comment body as HTML. Use `<@member_public_id>` to @mention a member." },
      },
      required: ["subject_type", "subject_id", "body_html"],
    ))

    private

    def execute
      require_scope!("write_post")
      actor, organization, member = organization_context!

      subject = load_subject(organization)
      authorize!(actor, subject, :create_comment?)

      params = ActionController::Parameters.new(body_html: enrich_mentions(input[:body_html])).permit!
      comment = Comment.create_comment(params: params, member: member, subject: subject)

      if comment.errors.empty?
        data_response(serialize(CommentSerializer, comment, organization: organization, member: member))
      else
        error("Could not add comment: #{comment.errors.full_messages.to_sentence}")
      end
    end

    def load_subject(organization)
      case input[:subject_type]
      when "post"
        organization.kept_posts.find_by!(public_id: input[:subject_id])
      when "note"
        organization.notes.kept.find_by!(public_id: input[:subject_id])
      else
        raise ToolError, "subject_type must be 'post' or 'note'."
      end
    end
  end
end
