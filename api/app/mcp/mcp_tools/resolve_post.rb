# frozen_string_literal: true

module McpTools
  # Resolves or unresolves a post as the connected user. Requires the `write_post`
  # scope and runs the same Post#resolve!/#unresolve! and authorization as the REST
  # API's Api::V1::Posts::ResolutionsController (create=resolve, destroy=unresolve).
  class ResolvePost < McpTool
    tool_name "resolve_post"
    description "Resolve or unresolve a post as the connected user. " \
      "Set resolved to false to unresolve; defaults to resolving. Requires the write_post scope."
    input_schema(org_scoped_schema(
      properties: {
        post_id: { type: "string", description: "The public id of the post to resolve or unresolve." },
        resolved: { type: "boolean", description: "true (default) to resolve, false to unresolve." },
        resolve_html: { type: "string", description: "Optional HTML note describing the resolution." },
        comment_id: { type: "string", description: "Optional public id of an existing comment to mark as the resolution." },
      },
      required: ["post_id"],
    ))

    private

    def execute
      require_scope!("write_post")
      actor, organization, member = organization_context!

      post = organization.kept_published_posts.find_by!(public_id: input[:post_id])
      authorize!(actor, post, :resolve?)

      resolved = input.key?(:resolved) ? input[:resolved] : true

      if resolved
        post.resolve!(actor: member, html: input[:resolve_html], comment_id: input[:comment_id])
      else
        post.unresolve!(actor: member)
      end

      data_response(serialize(PostSerializer, post, organization: organization, member: member))
    rescue ActiveRecord::RecordInvalid => e
      error("Could not update post resolution: #{e.message}")
    end
  end
end
