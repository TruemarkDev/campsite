# frozen_string_literal: true

module McpTools
  # Updates an existing post as the connected user. Requires the `write_post`
  # scope and runs the same Post::UpdatePost service + authorization as
  # Api::V1::PostsController#update.
  class UpdatePost < McpTool
    tool_name "update_post"
    description "Update an existing post (title, body, or project) as the connected user. " \
      "To @mention a member, put `<@member_public_id>` in description_html (get ids from list_members). " \
      "Requires the write_post scope."
    input_schema(org_scoped_schema(
      properties: {
        post_id: { type: "string", description: "The public id of the post to update." },
        title: { type: "string", description: "New post title." },
        description_html: { type: "string", description: "New body HTML; use `<@member_public_id>` to mention." },
        project_id: { type: "string", description: "Optional project public id to move the post to." },
      },
      required: ["post_id"],
    ))

    private

    def execute
      require_scope!("write_post")
      actor, organization, member = organization_context!

      post = organization.kept_published_posts.find_by!(public_id: input[:post_id])
      authorize!(actor, post, :update?)

      project = if input[:project_id].present?
        policy_scope(actor, organization.projects).find_by!(public_id: input[:project_id])
      end

      attrs = {}
      attrs[:title] = input[:title] if input[:title].present?
      attrs[:description_html] = enrich_mentions(input[:description_html]) if input[:description_html].present?
      params = ActionController::Parameters.new(attrs).permit!

      post.update_post(actor: member, organization: organization, project: project, params: params)

      if post.errors.empty?
        data_response(serialize(PostSerializer, post, organization: organization, member: member))
      else
        error("Could not update post: #{post.errors.full_messages.to_sentence}")
      end
    end
  end
end
