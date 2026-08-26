# frozen_string_literal: true

module Api
  module V1
    module Integrations
      module Zapier
        class BaseController < ActionController::API
          include RequestRescuable
          include RequestReturnable

          READ_SCOPE = "read_organization"
          WRITE_SCOPE = "write_organization"

          before_action :authenticate

          private

          def authenticate
            head(:unauthorized) unless valid_integration? || valid_zapier_oauth_token?
          end

          def valid_integration?
            token.present? && integration&.valid? && integration.owner_type == Organization.polymorphic_name
          end

          def valid_zapier_oauth_token?
            doorkeeper_token&.accessible? &&
              doorkeeper_token.owned_by_organization? &&
              doorkeeper_token.application&.kept? &&
              doorkeeper_token.application.zapier? &&
              doorkeeper_token.scopes.exists?(required_oauth_scope)
          end

          def required_oauth_scope
            request.get? || request.head? ? READ_SCOPE : WRITE_SCOPE
          end

          def token
            @token ||= request.headers["x-campsite-zapier-token"]
          end

          def integration
            @integration ||= Integration.zapier.find_by(token: token)
          end

          def current_oauth_application
            @oauth_application ||= doorkeeper_token&.application
          end

          def current_organization
            @current_organization ||= if valid_integration?
              integration.owner
            elsif valid_zapier_oauth_token?
              doorkeeper_token.resource_owner
            end
          end
        end
      end
    end
  end
end
