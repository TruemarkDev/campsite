# frozen_string_literal: true

# Remote MCP server mounted in the Rails API, served over Streamable HTTP at `/mcp`.
#
# Each request is authenticated with a Doorkeeper bearer token that carries the
# `mcp` scope; the token's resource owner (a User) becomes the acting identity for
# every tool. The JSON-RPC framing (initialize / tools/list / tools/call) is
# handled by the `mcp` gem; we own auth, the Current context, and dispatch.
class McpController < ActionController::API
  include McpDiscoverable

  before_action :require_mcp_enabled!
  before_action :authenticate_mcp!
  before_action :require_mcp_scope!

  def handle
    # No server-initiated streaming for this tools-only server: clients use POST
    # for JSON-RPC. GET (SSE stream) is unsupported; DELETE (end session) is a no-op.
    return head(:method_not_allowed) if request.get?
    return head(:no_content) if request.delete?

    context = McpRequestContext.new(token: doorkeeper_token)
    server = McpServer.build(context: context)

    response_json = server.handle_json(request.raw_post)

    if response_json.nil?
      # The request was a notification (e.g. notifications/initialized); no response body.
      head(:accepted)
    else
      render(json: response_json)
    end
  end

  private

  def authenticate_mcp!
    return if doorkeeper_token&.accessible?

    # RFC 9728: point unauthenticated clients at the protected-resource metadata so
    # they can discover how to authorize.
    response.set_header("WWW-Authenticate", %(Bearer resource_metadata="#{protected_resource_metadata_url}"))
    render(
      json: { error: "invalid_token", error_description: "A valid bearer access token is required." },
      status: :unauthorized,
    )
  end

  def require_mcp_scope!
    return if doorkeeper_token.scopes.exists?("mcp")

    render(
      json: { error: "insufficient_scope", error_description: "The 'mcp' scope is required to use the MCP server." },
      status: :forbidden,
    )
  end

  # Optional Flipper kill-switch for gradual rollout. The endpoint is enabled by
  # default; it is only blocked when an operator has registered the `mcp_server`
  # feature and turned it off (globally or for this user).
  def require_mcp_enabled!
    return if mcp_feature_enabled?

    head(:not_found)
  end

  def mcp_feature_enabled?
    feature = Flipper.feature(:mcp_server)
    return true unless feature.exist?

    Flipper.enabled?(:mcp_server, current_mcp_user)
  end

  def current_mcp_user
    return unless doorkeeper_token

    if defined?(@current_mcp_user)
      @current_mcp_user
    else
      @current_mcp_user = User.find_by(id: doorkeeper_token.resource_owner_id)
    end
  end
end
