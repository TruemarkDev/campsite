# frozen_string_literal: true

module McpTools
  class UpdateComment < McpTool
    tool_name "update_comment"
    description "Update the HTML body of a comment the connected user may edit. Requires write_post."
    input_schema(org_scoped_schema(
      properties: { comment_id: { type: "string" }, body_html: { type: "string" } },
      required: ["comment_id", "body_html"],
    ))

    private

    def execute
      require_scope!("write_post")
      actor, organization, member = organization_context!
      comment = Comment.serializer_preloads.kept.find_by!(public_id: input[:comment_id])
      raise ActiveRecord::RecordNotFound unless comment.organization == organization

      authorize!(actor, comment, :update?)
      comment.update!(body_html: enrich_mentions(input[:body_html]))
      data_response(serialize(CommentSerializer, comment, organization: organization, member: member))
    end
  end
end
