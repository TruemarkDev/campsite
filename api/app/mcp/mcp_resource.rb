# frozen_string_literal: true

# Campsite entities exposed as MCP **resources** — addressable, readable URIs a
# client can browse and attach as context, independent of the tool-call loop.
#
# A resource read is the same data the equivalent `read_*` tool returns: it resolves
# the org membership (and 2FA) exactly like a tool via McpOrganizationResolver, loads
# the record under the same Pundit policy, and renders the same Blueprinter
# serializer. Resources therefore add addressability and browsability, never new data
# or new authorization. Read-only — no resource mutates anything.
#
# URI scheme: `campsite://{org_slug}/{type}/{public_id}` where type is one of
# `posts`, `notes`, `threads`.
class McpResource
  # Raised for expected, user-facing resource failures (bad URI, unknown entity,
  # forbidden). The read handler maps it to a JSON-RPC error.
  class ResourceError < StandardError; end

  SCHEME = "campsite"
  URI_PATTERN = %r{\A#{SCHEME}://(?<org_slug>[^/]+)/(?<type>posts|notes|threads)/(?<public_id>[^/]+)\z}

  # How many recent entities of each kind to advertise per org in resources/list.
  LIST_LIMIT_PER_TYPE = 10

  # URI templates advertised by resources/templates/list — the addressing mechanism
  # for any entity, whether or not it appears in resources/list.
  def self.templates
    [
      MCP::ResourceTemplate.new(
        uri_template: "#{SCHEME}://{org_slug}/posts/{public_id}",
        name: "Campsite post",
        description: "A post by its public id, e.g. campsite://acme/posts/abc123.",
        mime_type: "application/json",
      ),
      MCP::ResourceTemplate.new(
        uri_template: "#{SCHEME}://{org_slug}/notes/{public_id}",
        name: "Campsite note",
        description: "A note by its public id, e.g. campsite://acme/notes/abc123.",
        mime_type: "application/json",
      ),
      MCP::ResourceTemplate.new(
        uri_template: "#{SCHEME}://{org_slug}/threads/{public_id}",
        name: "Campsite message thread",
        description: "A message thread by its public id, e.g. campsite://acme/threads/abc123.",
        mime_type: "application/json",
      ),
    ]
  end

  def initialize(context:)
    @context = context
  end

  # Resolve a `campsite://` URI to its resource contents (a one-element array, per the
  # MCP `resources/read` contract). Raises ResourceError / ActiveRecord::RecordNotFound
  # / Pundit::NotAuthorizedError, which the handler translates.
  def read(uri)
    match = URI_PATTERN.match(uri.to_s)
    raise ResourceError, "Unknown resource URI '#{uri}'. Expected campsite://{org_slug}/{posts|notes|threads}/{public_id}." unless match

    actor, organization, member = McpOrganizationResolver.resolve!(@context, match[:org_slug], ResourceError)
    json = render(match[:type], match[:public_id], actor: actor, organization: organization, member: member)

    [MCP::Resource::TextContents.new(uri: uri, mime_type: "application/json", text: json)]
  end

  # A bounded list of the connecting user's recent posts and notes across the orgs
  # they belong to, for client discovery. Threads are intentionally omitted (DMs are
  # noisy/private to enumerate); they remain addressable via the template. Each entry
  # is authorized by the same `policy_scope` the list tools use; orgs the user is
  # 2FA-blocked from are skipped.
  def list
    @context.user.kept_organization_memberships.includes(:organization).flat_map do |membership|
      organization = membership.organization
      next [] if organization.enforce_two_factor_authentication? && !@context.user.otp_enabled?

      Current.user = @context.user
      Current.organization = organization
      Current.organization_membership = membership

      recent_posts(organization) + recent_notes(organization)
    end
  end

  private

  def render(type, public_id, actor:, organization:, member:)
    case type
    when "posts"
      post = organization.kept_posts.feed_includes.find_by!(public_id: public_id)
      authorize!(actor, post, :show?)
      serialize(PostSerializer, post, organization: organization, member: member)
    when "notes"
      note = organization.notes.kept.serializer_preload.find_by!(public_id: public_id)
      authorize!(actor, note, :show?)
      serialize(NoteSerializer, note, organization: organization, member: member)
    when "threads"
      thread = MessageThread.serializer_includes.find_by!(public_id: public_id)
      # Pin the thread to the org named in the URI so a URI can't address a thread in
      # a different org; authorization (below) is what actually protects access.
      raise ActiveRecord::RecordNotFound unless thread.organization == organization

      authorize!(actor, thread, :list_messages?)
      serialize(MessageThreadSerializer, thread, organization: organization, member: member)
    end
  end

  def recent_posts(organization)
    actor = @context.actor
    return [] unless Pundit.policy!(actor, organization).list_posts?

    scope = Pundit.policy_scope!(actor, organization.kept_published_posts.leaves)
    scope.order(last_activity_at: :desc, id: :desc).limit(LIST_LIMIT_PER_TYPE).map do |post|
      MCP::Resource.new(
        uri: "#{SCHEME}://#{organization.slug}/posts/#{post.public_id}",
        name: post.title.presence || "Untitled post",
        description: "Post in #{organization.name}",
        mime_type: "application/json",
      )
    end
  end

  def recent_notes(organization)
    actor = @context.actor
    return [] unless Pundit.policy!(actor, organization).list_notes?

    scope = Pundit.policy_scope!(actor, organization.notes.kept)
    scope.order(last_activity_at: :desc, id: :desc).limit(LIST_LIMIT_PER_TYPE).map do |note|
      MCP::Resource.new(
        uri: "#{SCHEME}://#{organization.slug}/notes/#{note.public_id}",
        name: note.title.presence || "Untitled note",
        description: "Note in #{organization.name}",
        mime_type: "application/json",
      )
    end
  end

  def authorize!(actor, record, query)
    Pundit.authorize(actor, record, query)
  end

  def serialize(serializer, resource, organization:, member:)
    serializer.preload_and_render(
      resource,
      organization: organization,
      user: @context.user,
      member: member,
    )
  end
end
