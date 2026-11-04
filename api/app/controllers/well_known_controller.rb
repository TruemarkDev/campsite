# frozen_string_literal: true

# OAuth discovery metadata for remote MCP connectors (e.g. Claude).
#
# These unauthenticated endpoints let an MCP client self-discover how to authorize
# against Campsite's existing Doorkeeper provider:
#   * RFC 9728 — Protected Resource Metadata (describes the `/mcp` resource)
#   * RFC 8414 — Authorization Server Metadata (advertises authorize/token/registration)
#
# All URLs are built from the request origin so the same code works in dev and on
# Hatchbox without hardcoding the API host.
class WellKnownController < ActionController::API
  include McpDiscoverable

  # GET /.well-known/oauth-protected-resource(/mcp)
  def oauth_protected_resource
    render(json: {
      resource: mcp_resource_url,
      authorization_servers: [authorization_server_issuer],
      scopes_supported: supported_scopes,
      bearer_methods_supported: ["header"],
      resource_name: "Campsite",
      resource_documentation: "#{request.base_url}/mcp",
    })
  end

  # GET /.well-known/oauth-authorization-server(/mcp)
  def oauth_authorization_server
    metadata = {
      issuer: authorization_server_issuer,
      authorization_endpoint: "#{request.base_url}/v2/oauth/authorize",
      token_endpoint: "#{request.base_url}/v2/oauth/token",
      registration_endpoint: "#{request.base_url}/oauth/register",
      revocation_endpoint: "#{request.base_url}/v2/oauth/revoke",
      scopes_supported: supported_scopes,
      response_types_supported: ["code"],
      response_modes_supported: ["query"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      token_endpoint_auth_methods_supported: ["client_secret_basic", "client_secret_post", "none"],
      code_challenge_methods_supported: ["S256"],
    }

    if Oauth::Cimd.enabled?
      metadata[:client_id_metadata_document_supported] = true
      metadata[:authorization_response_iss_parameter_supported] = true
    end

    render(json: metadata)
  end
end
