# frozen_string_literal: true

module McpTools
  # Full-text search over an organization's posts. Mirrors
  # Api::V1::Search::PostsController#index (Elasticsearch via Searchkick), then
  # re-loads and authorizes the matches through the same policy scope.
  class SearchPosts < McpTool
    tool_name "search_posts"
    description "Search an organization's posts by text query. Optionally filter by project, author username, or tag."
    input_schema(org_scoped_schema(
      properties: {
        q: { type: "string", description: "The search query." },
        project_id: { type: "string", description: "Optional project public id to scope the search." },
        author: { type: "string", description: "Optional author username to filter by." },
        tag: { type: "string", description: "Optional tag name to filter by." },
        limit: { type: "integer", description: "Max results to return (default 10)." },
      },
      required: ["q"],
    ))

    private

    def execute
      actor, organization, member = organization_context!
      authorize!(actor, organization, :list_posts?)

      query = input[:q].to_s
      results = Post.scoped_search(
        query: query,
        sort_by_date: query.blank?,
        organization: organization,
        limit: input[:limit] || 10,
        project_public_id: input[:project_id],
        author_username: input[:author],
        tag_name: input[:tag],
      )

      ids = results&.pluck(:id) || []
      posts = policy_scope(actor, Post.in_order_of(:id, ids).includes(Post::FEED_INCLUDES))
      data = serialize(PostSerializer, posts, organization: organization, member: member)
      data_response(data)
    end
  end
end
