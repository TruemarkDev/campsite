# frozen_string_literal: true

require "test_helper"

module Users
  class SessionsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      host! "auth.campsite.com"
    end

    context "#new" do
      test "redirects to supported provider authorization URLs" do
        [
          "https://slack.com/oauth/v2/authorize?state=slack-state",
          "https://linear.app/oauth/authorize?state=linear-state",
          "https://www.figma.com/oauth?state=figma-state",
        ].each do |auth_url|
          get new_integrations_auth_path, params: { auth_url: auth_url }

          assert_redirected_to auth_url
        end
      end

      test "returns an error if auth_url is nil" do
        get new_integrations_auth_path

        assert_response :bad_request
        assert_includes response.body, "Invalid auth url"
      end

      test "rejects non-allowlisted auth URLs" do
        [
          "javascript:alert(1)",
          "http://slack.com/oauth/v2/authorize",
          "https://user:password@slack.com/oauth/v2/authorize",
          "https://slack.com:444/oauth/v2/authorize",
          "https://slack.com.attacker.example/oauth/v2/authorize",
          "https://attacker.example/oauth/v2/authorize",
          "https://linear.app/oauth/authorize/extra",
          "https://www.figma.com/oauth#fragment",
        ].each do |auth_url|
          get new_integrations_auth_path, params: { auth_url: auth_url }

          assert_response :bad_request
          assert_includes response.body, "Invalid auth url"
        end
      end
    end
  end
end
