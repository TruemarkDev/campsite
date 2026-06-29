# frozen_string_literal: true

# Shared URL/scope helpers for the MCP OAuth discovery surface. Mixed into the
# discovery endpoints and the MCP endpoint (which advertises the protected-resource
# metadata in its 401 `WWW-Authenticate` header).
module McpDiscoverable
  extend ActiveSupport::Concern

  # The MCP endpoint, identified as an OAuth protected resource (RFC 9728).
  def mcp_resource_url
    "#{request.base_url}/mcp"
  end

  # The authorization server is the same origin as the API host; its metadata is
  # served from `/.well-known/oauth-authorization-server` relative to this issuer.
  def authorization_server_issuer
    request.base_url
  end

  def protected_resource_metadata_url
    "#{request.base_url}/.well-known/oauth-protected-resource"
  end

  # Every configured Doorkeeper scope is selectable by a connector, including `mcp`.
  def supported_scopes
    Doorkeeper.config.scopes.all
  end
end
