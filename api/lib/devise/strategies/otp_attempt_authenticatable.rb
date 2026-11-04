# frozen_string_literal: true

module Devise
  module Strategies
    class OtpAttemptAuthenticatable < Devise::Strategies::Base
      def authenticate!
        resource = TwoFactorChallenge.user(session)

        if resource && validate_otp(resource)
          TwoFactorChallenge.consume!(session)
          success!(resource)
        else
          TwoFactorChallenge.record_failure!(session)
          fail!(:invalid_otp_code)
        end
      end

      private

      def validate_otp(resource)
        return true unless resource.otp_enabled?
        return if params[scope]["otp_attempt"].nil?

        resource.validate_and_consume_otp!(params[scope]["otp_attempt"])
      end
    end
  end
end
