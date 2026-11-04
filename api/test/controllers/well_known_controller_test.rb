# frozen_string_literal: true

require "test_helper"

class WellKnownControllerTest < ActionDispatch::IntegrationTest
  describe "#oauth_protected_resource" do
    test "describes the MCP endpoint and points at the authorization server" do
      get("/.well-known/oauth-protected-resource")

      assert_response :ok
      assert_match(%r{/mcp\z}, json_response["resource"])
      assert_includes json_response["authorization_servers"], "http://www.example.com"
      assert_includes json_response["scopes_supported"], "mcp"
      assert_equal ["header"], json_response["bearer_methods_supported"]
    end

    test "is also served at the resource-suffixed path" do
      get("/.well-known/oauth-protected-resource/mcp")

      assert_response :ok
      assert_match(%r{/mcp\z}, json_response["resource"])
    end
  end

  describe "#oauth_authorization_server" do
    test "advertises authorize/token/registration endpoints, PKCE, and the mcp scope" do
      get("/.well-known/oauth-authorization-server")

      assert_response :ok
      assert_equal "http://www.example.com/v2/oauth/authorize", json_response["authorization_endpoint"]
      assert_equal "http://www.example.com/v2/oauth/token", json_response["token_endpoint"]
      assert_equal "http://www.example.com/oauth/register", json_response["registration_endpoint"]
      assert_includes json_response["code_challenge_methods_supported"], "S256"
      assert_includes json_response["scopes_supported"], "mcp"
      assert_includes json_response["grant_types_supported"], "authorization_code"
      assert_nil json_response["client_id_metadata_document_supported"]
      assert_nil json_response["authorization_response_iss_parameter_supported"]
    end

    test "advertises CIMD and authorization response issuer support only when enabled" do
      Flipper.enable(Oauth::Cimd::FEATURE_NAME)

      get("/.well-known/oauth-authorization-server")

      assert_response :ok
      assert_equal true, json_response["client_id_metadata_document_supported"]
      assert_equal true, json_response["authorization_response_iss_parameter_supported"]
      assert_equal "http://www.example.com/oauth/register", json_response["registration_endpoint"]
    end
  end
end
