# frozen_string_literal: true

module McpTools
  # Reads a single post and (when permitted) its top-level comments. Mirrors
  # Api::V1::PostsController#show + Posts::PostCommentsController#index.
  class ReadPost < McpTool
    tool_name "read_post"
    description "Read a single post by its public id, including its top-level comments."
    input_schema(org_scoped_schema(
      properties: {
        post_id: { type: "string", description: "The public id of the post to read." },
      },
      required: ["post_id"],
      paginated: true,
    ))

    private

    def execute
      actor, organization, member = organization_context!

      post = organization.kept_posts.feed_includes.find_by!(public_id: input[:post_id])
      authorize!(actor, post, :show?)
      post_data = serialize(PostSerializer, post, organization: organization, member: member)

      comments_data = nil
      if Pundit.policy!(actor, post).list_comments?
        comments = post.kept_comments.root.serializer_preloads
        page = paginate(comments, order: :desc)
        comments_data = serialize(CommentPageSerializer, page, organization: organization, member: member)
      end

      data_response({ "post" => post_data, "comments" => comments_data })
    end
  end
end
