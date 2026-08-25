# frozen_string_literal: true

require "test_helper"

module Doorkeeper
  class CustomAuthorizationsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      host! "auth.campsite.com"
      @member = create(:organization_membership)
      @user = @member.user
    end

    context "#new" do
      test "shows validated CIMD identity and destination during consent" do
        Flipper.enable(Oauth::Cimd::FEATURE_NAME)
        oauth_application = create(
          :oauth_application,
          provider: :mcp_cimd,
          uid: "https://client.example/oauth/metadata.json",
          name: "Example Client",
          redirect_uri: "https://callback.example/oauth/callback",
          scopes: "mcp read_user",
          confidential: false,
        )
        Oauth::Cimd::Resolver.any_instance.stubs(:resolve!).returns(oauth_application)

        sign_in @user
        get oauth_authorization_path, params: {
          client_id: oauth_application.uid,
          response_type: "code",
          redirect_uri: oauth_application.redirect_uri,
          scope: "mcp read_user",
          code_challenge: "challenge",
          code_challenge_method: "S256",
        }

        assert_response :ok
        assert_includes response.body, "Example Client"
        assert_includes response.body, "client.example"
        assert_includes response.body, "callback.example"
        assert_includes response.body, "mcp, read_user"
      end

      test "requires S256 PKCE and byte-for-byte redirect matching for CIMD clients" do
        Flipper.enable(Oauth::Cimd::FEATURE_NAME)
        oauth_application = create(
          :oauth_application,
          provider: :mcp_cimd,
          uid: "https://client.example/oauth/metadata.json",
          redirect_uri: "https://client.example/callback?a=1&b=2",
          confidential: false,
        )
        Oauth::Cimd::Resolver.any_instance.stubs(:resolve!).returns(oauth_application)
        sign_in @user

        get oauth_authorization_path, params: {
          client_id: oauth_application.uid,
          response_type: "code",
          redirect_uri: oauth_application.redirect_uri,
        }

        assert_response :bad_request
        assert_equal "invalid_request", json_response["error"]

        get oauth_authorization_path, params: {
          client_id: oauth_application.uid,
          response_type: "code",
          redirect_uri: "https://client.example/callback?b=2&a=1",
          code_challenge: "challenge",
          code_challenge_method: "S256",
        }

        assert_response :bad_request
        assert_equal "invalid_redirect_uri", json_response["error"]
      end

      test "does not redirect when CIMD metadata cannot be fetched" do
        Flipper.enable(Oauth::Cimd::FEATURE_NAME)
        Oauth::Cimd::Resolver.any_instance.stubs(:resolve!).raises(Oauth::Cimd::FetchError)
        sign_in @user

        get oauth_authorization_path, params: {
          client_id: "https://client.example/oauth/metadata.json",
          response_type: "code",
          redirect_uri: "https://attacker.example/callback",
          code_challenge: "challenge",
          code_challenge_method: "S256",
        }

        assert_response :unauthorized
        assert_equal "invalid_client", json_response["error"]
        assert_equal "http://auth.campsite.com", json_response["iss"]
      end

      test "does not include the organization picker when creating an AccessGrant for a user" do
        oauth_application = create(:oauth_application)

        sign_in @user
        get oauth_authorization_path, params: {
          client_id: oauth_application.uid,
          response_type: "code",
          redirect_uri: oauth_application.redirect_uri,
        }

        assert_response :ok
        assert_not_includes response.body, "Organization"
      end

      # Doorkeeper >= 5.7 refuses to auto-approve an authorization when
      # `custom_access_token_attributes` is configured (`can_authorize_response?`), because a
      # pre-existing token may carry different attribute values than the ones this authorization
      # would produce. We configure `[:resource_owner_type, :resource_owner_id]`, so a matching
      # token no longer short-circuits to a redirect — the consent screen is rendered instead.
      test "renders the consent screen even when a matching access token exists" do
        oauth_application = create(:oauth_application)
        access_token = create(:access_token, application: oauth_application, resource_owner_id: @user.id)

        sign_in @user
        get oauth_authorization_path, params: {
          client_id: oauth_application.uid,
          response_type: "code",
          redirect_uri: oauth_application.redirect_uri,
          scope: access_token.scopes,
        }

        assert_response :ok
        assert_not_includes response.body, "Organization"
      end

      test "includes the organization picker when creating an AccessGrant for an organization" do
        oauth_application = create(:oauth_application, :zapier)

        sign_in @user
        get oauth_authorization_path, params: {
          client_id: oauth_application.uid,
          response_type: "code",
          redirect_uri: oauth_application.redirect_uri,
        }

        assert_response :ok
        assert_includes response.body, "Organization"
      end

      test "returns not found when the application is discarded" do
        oauth_application = create(:oauth_application, discarded_at: 5.minutes.ago)

        sign_in @user
        get oauth_authorization_path, params: {
          client_id: oauth_application.uid,
          response_type: "code",
          redirect_uri: oauth_application.redirect_uri,
        }

        assert_response :not_found
      end
    end

    context "#create" do
      test "adds RFC 9207 issuer to successful authorization responses when enabled" do
        Flipper.enable(Oauth::Cimd::FEATURE_NAME)
        oauth_application = create(:oauth_application, redirect_uri: "https://client.example/callback")

        sign_in @user
        post oauth_authorization_path, params: {
          client_id: oauth_application.uid,
          state: "state",
          redirect_uri: oauth_application.redirect_uri,
          response_type: "code",
        }

        assert_response :redirect
        assert_equal "http://auth.campsite.com", Rack::Utils.parse_query(URI(response.redirect_url).query)["iss"]
      end

      test "redeems a CIMD authorization code against the same persisted client" do
        Flipper.enable(Oauth::Cimd::FEATURE_NAME)
        oauth_application = create(
          :oauth_application,
          provider: :mcp_cimd,
          uid: "https://client.example/oauth/metadata.json",
          redirect_uri: "https://client.example/callback",
          scopes: "mcp read_user",
          confidential: false,
        )
        Oauth::Cimd::Resolver.any_instance.stubs(:resolve!).returns(oauth_application)
        verifier = "v" * 43
        challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)

        sign_in @user
        post oauth_v2_authorizations_path, params: {
          client_id: oauth_application.uid,
          state: "state",
          redirect_uri: oauth_application.redirect_uri,
          response_type: "code",
          scope: "mcp read_user",
          code_challenge: challenge,
          code_challenge_method: "S256",
        }
        code = Rack::Utils.parse_query(URI(response.redirect_url).query)["code"]

        assert code.present?

        post oauth_v2_tokens_path, params: {
          grant_type: "authorization_code",
          code: code,
          redirect_uri: oauth_application.redirect_uri,
          client_id: oauth_application.uid,
          code_verifier: verifier,
        }

        assert_response :ok
        assert json_response["access_token"].present?
        access_token_value = json_response["access_token"]
        access_token = AccessToken.last!
        assert_equal oauth_application, access_token.application

        post "/v2/oauth/revoke", params: {
          client_id: oauth_application.uid,
          token: access_token_value,
        }

        assert_response :ok
        assert_predicate access_token.reload, :revoked?
      end

      test "keeps DCR registration, authorization, and token redemption working" do
        redirect_uri = "https://dcr-client.example/callback"
        post "/oauth/register",
          params: {
            client_name: "DCR Client",
            redirect_uris: [redirect_uri],
            token_endpoint_auth_method: "none",
            scope: "mcp read_user",
          },
          as: :json
        client_id = json_response["client_id"]
        verifier = "v" * 43
        challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)

        sign_in @user
        post oauth_v2_authorizations_path, params: {
          client_id: client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: "mcp read_user",
          code_challenge: challenge,
          code_challenge_method: "S256",
        }
        code = Rack::Utils.parse_query(URI(response.redirect_url).query)["code"]

        post oauth_v2_tokens_path, params: {
          grant_type: "authorization_code",
          code: code,
          redirect_uri: redirect_uri,
          client_id: client_id,
          code_verifier: verifier,
        }

        assert_response :ok
        assert json_response["access_token"].present?
      end

      test "adds RFC 9207 issuer to non-redirectable invalid-client errors when enabled" do
        Flipper.enable(Oauth::Cimd::FEATURE_NAME)

        sign_in @user
        post oauth_authorization_path, params: {
          client_id: "missing-client",
          redirect_uri: "https://client.example/callback",
          response_type: "code",
        }

        assert_response :unauthorized
        assert_equal "invalid_client", json_response["error"]
        assert_equal "http://auth.campsite.com", json_response["iss"]
      end

      test "adds RFC 9207 issuer to redirected denial responses when enabled" do
        Flipper.enable(Oauth::Cimd::FEATURE_NAME)
        oauth_application = create(:oauth_application, redirect_uri: "https://client.example/callback")

        sign_in @user
        delete oauth_authorization_path, params: {
          client_id: oauth_application.uid,
          state: "state",
          redirect_uri: oauth_application.redirect_uri,
          response_type: "code",
        }

        assert_response :redirect
        query = Rack::Utils.parse_query(URI(response.redirect_url).query)
        assert_equal "access_denied", query["error"]
        assert_equal "http://auth.campsite.com", query["iss"]
      end

      test "adds RFC 9207 issuer to form-post response bodies when enabled" do
        Flipper.enable(Oauth::Cimd::FEATURE_NAME)
        oauth_application = create(:oauth_application, redirect_uri: "https://client.example/callback")

        sign_in @user
        post oauth_authorization_path, params: {
          client_id: oauth_application.uid,
          redirect_uri: oauth_application.redirect_uri,
          response_type: "code",
          response_mode: "form_post",
        }

        assert_response :ok
        assert_includes response.body, 'name="iss"'
        assert_includes response.body, 'value="http://auth.campsite.com"'
      end

      test "creates an AccessGrant for a user by default" do
        oauth_application = create(:oauth_application)

        sign_in @user

        post oauth_authorization_path, params: {
          client_id: oauth_application.uid,
          state: "state",
          redirect_uri: oauth_application.redirect_uri,
          response_type: "code",
        }

        assert_response :redirect
        assert_includes response.redirect_url, "code="
        access_grant = AccessGrant.last!
        assert_equal @user.id, access_grant.resource_owner_id
        assert_equal User.polymorphic_name, access_grant.resource_owner_type
      end

      test "creates an AccessGrant for a user when specifying resource_owner_id" do
        oauth_application = create(:oauth_application)

        sign_in @user

        post oauth_authorization_path, params: {
          client_id: oauth_application.uid,
          state: "state",
          redirect_uri: oauth_application.redirect_uri,
          response_type: "code",
          resource_owner_id: @user.id,
        }

        assert_response :redirect
        assert_includes response.redirect_url, "code="
        access_grant = AccessGrant.last!
        assert_equal @user.id, access_grant.resource_owner_id
        assert_equal User.polymorphic_name, access_grant.resource_owner_type
      end

      test "user can't create an AccessGrant for another user" do
        other_user = create(:user)
        oauth_application = create(:oauth_application)

        sign_in @user

        post oauth_authorization_path, params: {
          client_id: oauth_application.uid,
          state: "state",
          redirect_uri: oauth_application.redirect_uri,
          response_type: "code",
          resource_owner_id: other_user.id,
        }

        assert_response :forbidden
      end

      test "rejects unknown resource owner types without constantizing them" do
        oauth_application = create(:oauth_application)
        sign_in @user

        post oauth_authorization_path, params: {
          client_id: oauth_application.uid,
          state: "state",
          redirect_uri: oauth_application.redirect_uri,
          response_type: "code",
          resource_owner_type: "Kernel",
          resource_owner_id: @user.id,
        }

        assert_response :not_found
        assert_nil AccessGrant.last
      end

      test "creates an AccessGrant for an organization" do
        oauth_application = create(:oauth_application, :zapier, redirect_uri: "https://example.com/callback")

        sign_in @user

        post oauth_authorization_path, params: {
          client_id: oauth_application.uid,
          state: "state",
          redirect_uri: oauth_application.redirect_uri,
          response_type: "code",
          resource_owner_type: "Organization",
          resource_owner_id: @member.organization.id,
        }

        assert_response :redirect
        assert_includes response.redirect_url, "code="
        access_grant = AccessGrant.last!
        assert_equal @member.organization.id, access_grant.resource_owner_id
        assert_equal Organization.polymorphic_name, access_grant.resource_owner_type
      end

      test "user can't create an AccessGrant for an organization they aren't a member of" do
        other_organization = create(:organization)
        oauth_application = create(:oauth_application, :zapier, redirect_uri: "https://example.com/callback")

        sign_in @user

        post oauth_authorization_path, params: {
          client_id: oauth_application.uid,
          state: "state",
          redirect_uri: oauth_application.redirect_uri,
          response_type: "code",
          resource_owner_type: "Organization",
          resource_owner_id: other_organization.id,
        }

        assert_response :forbidden
      end

      context "#v2" do
        test "user can't create an AccessGrant for another user" do
          other_user = create(:user)
          oauth_application = create(:oauth_application)

          sign_in @user

          post oauth_v2_authorizations_path, params: {
            client_id: oauth_application.uid,
            state: "state",
            redirect_uri: oauth_application.redirect_uri,
            response_type: "code",
            resource_owner_id: other_user.id,
          }

          assert_response :forbidden
        end

        test "user can't create an AccessGrant for an organization they aren't a member of" do
          other_organization = create(:organization)
          oauth_application = create(:oauth_application, :zapier, redirect_uri: "https://example.com/callback")

          sign_in @user

          post oauth_v2_authorizations_path, params: {
            client_id: oauth_application.uid,
            state: "state",
            redirect_uri: oauth_application.redirect_uri,
            response_type: "code",
            resource_owner_type: "Organization",
            resource_owner_id: other_organization.id,
          }

          assert_response :forbidden
        end
      end
    end
  end
end
