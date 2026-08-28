# frozen_string_literal: true

module McpTools
  class RemovePost < McpTool
    tool_name "remove_post"
    description "Discard a post the connected user may remove. Requires write_post."
    input_schema(org_scoped_schema(properties: { post_id: { type: "string" } }, required: ["post_id"]))

    private

    def execute
      require_scope!("write_post")
      actor, organization, member = organization_context!
      post = organization.kept_posts.find_by!(public_id: input[:post_id])
      authorize!(actor, post, :destroy?)
      post.discard_by_actor(member)
      data_response({ removed: true, post_id: post.public_id })
    end
  end
end
