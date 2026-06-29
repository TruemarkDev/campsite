# frozen_string_literal: true

module McpTools
  # Replies to an existing comment on a post or note as the connected user,
  # creating a threaded reply. Requires the `write_post` scope and runs the same
  # Comment::CreateComment service and authorization as the REST API. Complements
  # add_comment, which starts a new comment thread.
  class ReplyToComment < McpTool
    tool_name "reply_to_comment"
    description "Reply to an existing comment on a post or note as the connected user, creating a threaded reply. " \
      "To @mention a member, put `<@member_public_id>` in body_html (get ids from list_members). Requires the write_post scope."
    input_schema(org_scoped_schema(
      properties: {
        comment_id: { type: "string", description: "Public id of the parent comment to reply to." },
        body_html: { type: "string", description: "Reply body as HTML. Use `<@member_public_id>` to @mention a member." },
      },
      required: ["comment_id", "body_html"],
    ))

    private

    def execute
      require_scope!("write_post")
      actor, organization, member = organization_context!

      parent = load_parent(organization)
      authorize!(actor, parent.subject, :create_comment?)

      params = ActionController::Parameters.new(body_html: enrich_mentions(input[:body_html])).permit!
      comment = Comment.create_comment(params: params, member: member, parent: parent)

      if comment.errors.empty?
        data_response(serialize(CommentSerializer, comment, organization: organization, member: member))
      else
        error("Could not reply to comment: #{comment.errors.full_messages.to_sentence}")
      end
    end

    # Find the parent comment and confirm it lives in the resolved organization.
    # A comment delegates `organization` to its subject (post/note), so an id from
    # another org is rejected as not found — the cross-org guard.
    def load_parent(organization)
      parent = Comment.find_by!(public_id: input[:comment_id])
      raise ActiveRecord::RecordNotFound if parent.organization != organization

      parent
    end
  end
end
