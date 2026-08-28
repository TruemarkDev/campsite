# frozen_string_literal: true

module McpTools
  class RemoveComment < McpTool
    tool_name "remove_comment"
    description "Discard a comment the connected user may remove. Requires write_post."
    input_schema(org_scoped_schema(properties: { comment_id: { type: "string" } }, required: ["comment_id"]))

    private

    def execute
      require_scope!("write_post")
      actor, organization, member = organization_context!
      comment = Comment.kept.find_by!(public_id: input[:comment_id])
      raise ActiveRecord::RecordNotFound unless comment.organization == organization

      authorize!(actor, comment, :destroy?)
      comment.discard_by_actor(member)
      data_response({ removed: true, comment_id: comment.public_id })
    end
  end
end
