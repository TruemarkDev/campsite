# frozen_string_literal: true

require "test_helper"

module Oauth
  class RegistrationsControllerTest < ActionDispatch::IntegrationTest
    describe "#create" do
      test "registers a confidential client and returns credentials" do
        assert_difference -> { OauthApplication.count }, 1 do
          post(
            "/oauth/register",
            params: {
              client_name: "Claude",
              redirect_uris: ["https://claude.ai/api/mcp/auth_callback"],
              scope: "mcp read_organization write_post",
            },
            as: :json,
          )
        end

        assert_response :created
        assert_equal "Claude", json_response["client_name"]
        assert json_response["client_id"].present?
        assert json_response["client_secret"].present?
        assert_equal "client_secret_basic", json_response["token_endpoint_auth_method"]
        assert_includes json_response["scope"].split, "mcp"

        application = OauthApplication.find_by(uid: json_response["client_id"])
        assert_equal ["https://claude.ai/api/mcp/auth_callback"], application.redirect_uri.split
      end

      test "registers a public client (token_endpoint_auth_method=none) without a secret" do
        post(
          "/oauth/register",
          params: {
            client_name: "Native MCP Client",
            redirect_uris: ["https://example.com/callback"],
            token_endpoint_auth_method: "none",
          },
          as: :json,
        )

        assert_response :created
        assert_equal "none", json_response["token_endpoint_auth_method"]
        assert_nil json_response["client_secret"]
      end

      test "falls back to default scopes when none are requested" do
        post("/oauth/register", params: { redirect_uris: ["https://example.com/callback"] }, as: :json)

        assert_response :created
        assert_includes json_response["scope"].split, "mcp"
        assert_not_includes json_response["scope"].split, "write_post"
        assert_not_includes json_response["scope"].split, "write_message"
      end

      test "rejects unsupported scopes instead of silently replacing them" do
        post(
          "/oauth/register",
          params: { redirect_uris: ["https://example.com/callback"], scope: "mcp unknown_scope" },
          as: :json,
        )

        assert_response :bad_request
        assert_equal "invalid_client_metadata", json_response["error"]
        assert_includes json_response["error_description"], "unknown_scope"
      end

      test "rejects unsupported token endpoint authentication methods" do
        post(
          "/oauth/register",
          params: { redirect_uris: ["https://example.com/callback"], token_endpoint_auth_method: "client_secret_jwt" },
          as: :json,
        )

        assert_response :bad_request
        assert_equal "invalid_client_metadata", json_response["error"]
      end

      test "rejects a forbidden redirect URI scheme" do
        assert_no_difference -> { OauthApplication.count } do
          post(
            "/oauth/register",
            params: {
              redirect_uris: ["javascript:alert(1)"],
            },
            as: :json,
          )
        end

        assert_response :bad_request
        assert_equal "invalid_redirect_uri", json_response["error"]
      end

      test "requires at least one redirect URI" do
        post("/oauth/register", params: { client_name: "No Redirect" }, as: :json)

        assert_response :bad_request
        assert_equal "invalid_redirect_uri", json_response["error"]
      end
    end
  end
end
