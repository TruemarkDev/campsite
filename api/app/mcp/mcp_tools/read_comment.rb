# frozen_string_literal: true

module McpTools
  class ReadComment < McpTool
    tool_name "read_comment"
    description "Read a comment by public id, including its threaded replies when serialized."
    input_schema(org_scoped_schema(properties: { comment_id: { type: "string" } }, required: ["comment_id"]))

    private

    def execute
      actor, organization, member = organization_context!
      comment = Comment.serializer_preloads.kept.find_by!(public_id: input[:comment_id])
      raise ActiveRecord::RecordNotFound unless comment.organization == organization

      authorize!(actor, comment, :show?)
      data_response(serialize(CommentSerializer, comment, organization: organization, member: member))
    end
  end
end
