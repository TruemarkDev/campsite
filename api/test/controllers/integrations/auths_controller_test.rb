# frozen_string_literal: true

require "test_helper"

module Users
  class SessionsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      host! "auth.campsite.com"
    end

    context "#new" do
      test "redirects to auth_url from params" do
        auth_url = "https://example.com"
        get new_integrations_auth_path, params: { auth_url: auth_url }

        assert_redirected_to auth_url
      end

      test "returns an error if auth_url is nil" do
        get new_integrations_auth_path

        assert_response :bad_request
        assert_includes response.body, "Invalid auth url"
      end

      test "rejects non-HTTP and credential-bearing auth URLs" do
        ["javascript:alert(1)", "https://user:password@example.com/oauth"].each do |auth_url|
          get new_integrations_auth_path, params: { auth_url: auth_url }

          assert_response :bad_request
          assert_includes response.body, "Invalid auth url"
        end
      end
    end
  end
end
