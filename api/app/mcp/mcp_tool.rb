# frozen_string_literal: true

# Base class for every Campsite MCP tool.
#
# A tool wraps the same models, services, Pundit policies, and Blueprinter
# serializers the `/api/v1` REST API uses — it never bypasses authorization. Each
# org-scoped tool takes an `org_slug` argument; we resolve the user's kept
# membership there (multi-org parity with the frontend) and set the `Current`
# context exactly as a controller would before doing any work.
#
# Subclasses implement `#execute` and return an `MCP::Tool::Response`.
class McpTool < MCP::Tool
  # Raised for expected, user-facing failures (bad input, missing membership,
  # missing scope). Surfaced to the client as a tool-level error result, never a
  # transport crash.
  class ToolError < StandardError; end

  # Pagination arguments shared by every list tool (cursor-based, like the REST API).
  PAGINATION_PROPERTIES = {
    limit: { type: "integer", description: "Max items to return (1-100, default 50)." },
    after: { type: "string", description: "Pagination cursor: return items after this cursor." },
    before: { type: "string", description: "Pagination cursor: return items before this cursor." },
  }.freeze

  ORG_SLUG_PROPERTY = {
    org_slug: {
      type: "string",
      description: "Slug of the organization to act within. Call list_organizations to discover available slugs.",
    },
  }.freeze

  class << self
    # Invoked by MCP::Server. `server_context` is the gem's ServerContext wrapper,
    # which delegates unknown methods to our McpRequestContext (so `.user`,
    # `.actor`, `.scope?` all resolve).
    def call(server_context:, **input)
      new(context: server_context, input: input).run
    end

    # Build an input schema that always includes `org_slug`, merging extra
    # properties and required keys.
    def org_scoped_schema(properties: {}, required: [], paginated: false)
      props = ORG_SLUG_PROPERTY.merge(properties)
      props = props.merge(PAGINATION_PROPERTIES) if paginated
      {
        properties: props,
        required: (["org_slug"] + required.map(&:to_s)).uniq,
      }
    end
  end

  attr_reader :context, :input

  def initialize(context:, input:)
    @context = context
    @input = input
  end

  def run
    execute
  rescue Pundit::NotAuthorizedError
    error("You are not authorized to perform this action.")
  rescue ActiveRecord::RecordNotFound
    error("The requested resource could not be found.")
  rescue ToolError => e
    error(e.message)
  end

  private

  def execute
    raise NotImplementedError, "#{self.class} must implement #execute"
  end

  def user
    context.user
  end

  # Resolve the org membership for the `org_slug` argument, set the Current context,
  # and return [actor, organization, membership]. Raises ToolError if the user has
  # no kept membership in that org (no cross-org leakage).
  def organization_context!
    slug = input[:org_slug]
    raise ToolError, "An org_slug argument is required." if slug.blank?

    membership = context.membership_for(slug)
    unless membership
      raise ToolError, "You are not a member of an organization with slug '#{slug}'."
    end

    organization = membership.organization

    Current.user = user
    Current.organization = organization
    Current.organization_membership = membership

    [context.actor, organization, membership]
  end

  # Enforce that the connection was granted a specific write scope before mutating.
  def require_scope!(scope)
    return if context.scope?(scope)

    raise ToolError, "This action requires the '#{scope}' OAuth scope, which this connection was not granted."
  end

  def authorize!(actor, record, query)
    Pundit.authorize(actor, record, query)
  end

  # Expand the `<@member_public_id>` mention shorthand in user-supplied HTML into the
  # rich mention markup Campsite expects, so the model can tag people without
  # hand-writing `<span data-type="mention" …>`. No-op for blank input.
  def enrich_mentions(html)
    return html if html.blank?

    MentionsFormatter.new(html).replace
  end

  def policy_scope(actor, scope)
    Pundit.policy_scope!(actor, scope)
  end

  def paginate(scope, order:)
    CursorPagination.new(
      scope: scope,
      after: input[:after],
      before: input[:before],
      limit: input[:limit],
      order: order,
    ).run
  end

  # Render through the same serializer the REST API uses and return a parsed Hash.
  def serialize(serializer, resource, organization:, member:, options: {})
    JSON.parse(serializer.preload_and_render(
      resource,
      organization: organization,
      user: user,
      member: member,
      options: options,
    ))
  end

  def data_response(data)
    structured = data.is_a?(Hash) ? data : { "data" => data }
    MCP::Tool::Response.new(
      [{ type: "text", text: JSON.pretty_generate(data) }],
      structured_content: structured,
    )
  end

  def error(message)
    MCP::Tool::Response.new([{ type: "text", text: message }], error: true)
  end
end
