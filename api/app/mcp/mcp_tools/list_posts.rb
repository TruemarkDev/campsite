# frozen_string_literal: true

module McpTools
  # Lists published posts in an organization, optionally filtered to a single
  # project. Mirrors Api::V1::PostsController#index and Projects::PostsController#index.
  class ListPosts < McpTool
    tool_name "list_posts"
    description "List published posts in an organization, most recent first. " \
      "Optionally filter to a single project by its public id."
    input_schema(org_scoped_schema(
      properties: {
        project_id: { type: "string", description: "Optional project public id to filter posts to one project." },
        hide_resolved: { type: "boolean", description: "When true (with project_id), hide resolved posts." },
      },
      paginated: true,
    ))

    private

    def execute
      actor, organization, member = organization_context!

      if input[:project_id].present?
        project = organization.projects.find_by!(public_id: input[:project_id])
        authorize!(actor, project, :list_posts?)
        scope = project.kept_published_posts.leaves.feed_includes
        scope = scope.unresolved if input[:hide_resolved] == true
        order = { published_at: :desc, id: :desc }
      else
        authorize!(actor, organization, :list_posts?)
        scope = organization.kept_published_posts.leaves.feed_includes
        order = { last_activity_at: :desc, id: :desc }
      end

      page = paginate(policy_scope(actor, scope), order: order)
      data = serialize(PostPageSerializer, page, organization: organization, member: member)
      data_response(data)
    end
  end
end
