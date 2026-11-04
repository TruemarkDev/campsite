# frozen_string_literal: true

module McpTools
  # Creates a post under the connected user's identity. Requires the `write_post`
  # scope and runs the same Post::CreatePost service + validations as the REST API.
  class CreatePost < McpTool
    tool_name "create_post"
    description "Create a new post in an organization (optionally in a specific project) as the connected user. " \
      "To @mention a member, put `<@member_public_id>` in description_html (get ids from list_members). " \
      "Requires the write_post scope."
    input_schema(org_scoped_schema(
      properties: {
        title: { type: "string", description: "The post title." },
        description_html: { type: "string", description: "The post body as HTML. Use `<@member_public_id>` to @mention a member." },
        project_id: { type: "string", description: "Optional project public id; defaults to the org's general project." },
      },
      required: ["title"],
    ))

    private

    def execute
      require_scope!("write_post")
      actor, organization, member = organization_context!
      authorize!(actor, organization, :create_post?)

      project = if input[:project_id].present?
        organization.projects.find_by!(public_id: input[:project_id])
      else
        organization.general_project
      end
      authorize!(actor, project, :create_post?)

      params = ActionController::Parameters.new(
        title: input[:title],
        description_html: enrich_mentions(input[:description_html].to_s),
      ).permit!

      post = Post.create_post(
        params: params,
        parent: nil,
        project: project,
        organization: organization,
        member: member,
      )

      if post.errors.empty?
        data_response(serialize(PostSerializer, post, organization: organization, member: member))
      else
        error("Could not create post: #{post.errors.full_messages.to_sentence}")
      end
    end
  end
end
