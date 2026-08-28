# frozen_string_literal: true

require "test_helper"
require "test_helpers/rack_attack_helper"

module Users
  module Otp
    class SessionsControllerTest < ActionDispatch::IntegrationTest
      include Devise::Test::IntegrationHelpers
      include RackAttackHelper

      setup do
        host! "auth.campsite.com"
      end

      context "#new" do
        test "redirects to sign in page if otp not set" do
          get sign_in_otp_path

          assert_response :redirect
          assert_includes response.redirect_url, new_user_session_path
        end
      end

      context "#create" do
        test "authenticates a user with valid otp_attempt" do
          user = create(:user, :otp)

          # sign in and get redirected to otp
          post user_session_path, params: { user: { email: user.email, password: user.password } }
          assert_response :redirect
          assert_equal user, TwoFactorChallenge.user(controller.session)

          # sign in otop
          post sign_in_otp_path, params: { user: { otp_attempt: otp_attempt(user.otp_secret) } }

          assert_response :redirect
          warden = controller.session["warden.user.user.key"]
          assert_equal(warden.first.first, user.id)
          assert_nil flash[:alert]
        end

        test "does not authenticate a user with invalid otp_attempt" do
          user = create(:user, :otp)

          # sign in and get redirected to otp
          post user_session_path, params: { user: { email: user.email, password: user.password } }

          # sign in otp
          post sign_in_otp_path, params: { user: { otp_attempt: "invalid" } }

          assert_response :ok
          assert_nil controller.session["warden.user.user.key"]
          assert_not_nil flash[:alert]
        end

        test "expires the pre-authentication challenge" do
          user = create(:user, :otp)
          post user_session_path, params: { user: { email: user.email, password: user.password } }

          travel 11.minutes do
            get sign_in_otp_path
          end

          assert_response :redirect
          assert_includes response.redirect_url, new_user_session_path
          assert_nil TwoFactorChallenge.user(controller.session)
        end

        test "clears the challenge after repeated invalid attempts" do
          user = create(:user, :otp)
          post user_session_path, params: { user: { email: user.email, password: user.password } }

          TwoFactorChallenge::MAX_ATTEMPTS.times do
            post sign_in_otp_path, params: { user: { otp_attempt: "invalid" } }
          end

          assert_nil TwoFactorChallenge.user(controller.session)
        end

        test "rate limits two-factor attempts by client ip" do
          user = create(:user, :otp)
          post user_session_path, params: { user: { email: user.email, password: user.password } }
          ip = "203.0.113.10"

          enable_rack_attack do
            Rack::Attack::TWO_FACTOR_ATTEMPTS_LIMIT.times do
              Rack::Attack.cache.count("limit two factor attempts per ip:ip:#{ip}", Rack::Attack::TWO_FACTOR_ATTEMPTS_PERIOD)
            end

            post sign_in_otp_path,
              params: { user: { otp_attempt: otp_attempt(user.otp_secret) } },
              headers: { "HTTP_CF_CONNECTING_IP" => ip }

            assert_response :too_many_requests
          end
        end
      end
    end
  end
end
