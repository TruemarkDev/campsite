# frozen_string_literal: true

module Doorkeeper
  class CustomAuthorizationsController < AuthorizationsController
    include Pundit::Authorization
    include DatabaseRoleSwitchable
    include McpDiscoverable

    rescue_from Pundit::NotAuthorizedError, with: :render_forbidden

    around_action :force_database_writing_role, only: [:new]

    before_action :ensure_current_user_is_authorized_for_resource_owner, only: [:create]
    before_action :ensure_application_is_not_discarded
    before_action :ensure_cimd_request_is_valid

    private

    def ensure_current_user_is_authorized_for_resource_owner
      resource_owner_id = params[:resource_owner_id] || current_resource_owner.id
      resource_owner_class = params[:resource_owner_type]&.constantize || current_resource_owner.class

      authorize(resource_owner_class.find(resource_owner_id), :create_oauth_access_grant?)
    end

    def ensure_application_is_not_discarded
      return unless params[:client_id]

      if Oauth::Cimd.enabled? && Oauth::Cimd::ClientId.url_shaped?(params[:client_id])
        @oauth_application = OauthApplication.by_uid(params[:client_id])
        return if @oauth_application

        return render(
          status: :unauthorized,
          json: {
            error: "invalid_client",
            error_description: "Client metadata could not be validated.",
            iss: authorization_server_issuer,
          },
        )
      end

      @oauth_application = OauthApplication.kept.find_by(uid: params[:client_id])

      return if @oauth_application

      if Oauth::Cimd.enabled?
        render(
          status: :unauthorized,
          json: {
            error: "invalid_client",
            error_description: "Client could not be validated.",
            iss: authorization_server_issuer,
          },
        )
      else
        render_not_found
      end
    end

    def ensure_cimd_request_is_valid
      return unless @oauth_application&.mcp_cimd?

      unless params[:code_challenge].present? && params[:code_challenge_method] == "S256"
        return render_oauth_error("invalid_request", "CIMD clients must use S256 PKCE.")
      end

      registered_redirects = @oauth_application.redirect_uri.to_s.split
      return if registered_redirects.include?(params[:redirect_uri].to_s)

      Oauth::Cimd.instrument(:redirect_mismatch, host: URI.parse(@oauth_application.uid).host)
      render_oauth_error("invalid_redirect_uri", "Redirect URI is not registered for this client.")
    end

    def render_oauth_error(error, description)
      render(
        status: :bad_request,
        json: {
          error: error,
          error_description: description,
          iss: authorization_server_issuer,
        },
      )
    end

    def redirect_or_render(response)
      if Oauth::Cimd.enabled?
        response = Oauth::AuthorizationResponse.new(response, issuer: authorization_server_issuer)
        @authorize_response = response
      end

      super(response)
    end

    def render_forbidden(error = nil)
      message = error.is_a?(Pundit::NotAuthorizedError) ? "This action requires additional privileges." : error.message
      render(status: :forbidden, json: { code: "forbidden", message: message })
    end

    def render_not_found
      render(status: :not_found, json: { code: "not_found", message: "Not found" })
    end
  end
end
