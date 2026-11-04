# frozen_string_literal: true

module Oauth
  # OAuth 2.0 Dynamic Client Registration (RFC 7591).
  #
  # Lets a remote MCP client (e.g. Claude) register itself and obtain credentials
  # without an administrator hand-provisioning an OauthApplication, matching the
  # Notion/PostHog connector UX. Registration is intentionally open but throttled
  # (see config/initializers/rack_attack.rb) and grants no access on its own — a
  # human still signs in and consents before any token is issued.
  class RegistrationsController < ActionController::API
    # Schemes we never allow as redirect URIs, independent of Doorkeeper's own
    # HTTPS enforcement. Blocks the obvious script/exfiltration vectors.
    FORBIDDEN_REDIRECT_SCHEMES = ["javascript", "data", "file", "vbscript", "blob"].freeze
    SUPPORTED_TOKEN_ENDPOINT_AUTH_METHODS = ["client_secret_basic", "none"].freeze

    # Scopes granted by default when a client registers without requesting any.
    DEFAULT_SCOPES = "mcp read_organization read_user read_post read_project"

    def create
      redirect_uris = Array(params[:redirect_uris]).map(&:to_s).compact_blank

      if redirect_uris.empty?
        return render_registration_error("invalid_redirect_uri", "At least one redirect_uri is required.")
      end

      if (bad_uri = redirect_uris.find { |uri| !allowed_redirect_uri?(uri) })
        return render_registration_error("invalid_redirect_uri", "Redirect URI is not allowed: #{bad_uri}")
      end

      unless SUPPORTED_TOKEN_ENDPOINT_AUTH_METHODS.include?(token_endpoint_auth_method)
        return render_registration_error("invalid_client_metadata", "Unsupported token_endpoint_auth_method.")
      end

      if invalid_requested_scopes.any?
        return render_registration_error("invalid_client_metadata", "Unsupported scopes: #{invalid_requested_scopes.join(' ')}")
      end

      requested_scopes = requested_scope_string
      application = OauthApplication.new(
        name: client_name,
        redirect_uri: redirect_uris.join("\n"),
        scopes: requested_scopes,
        confidential: confidential_client?,
      )

      if application.save
        render(json: registration_response(application), status: :created)
      else
        render_registration_error("invalid_client_metadata", application.errors.full_messages.to_sentence)
      end
    end

    private

    def client_name
      params[:client_name].presence || "MCP Client"
    end

    # Public clients (native/SPA apps using PKCE) declare `none`; everyone else gets
    # a confidential client with a secret.
    def confidential_client?
      token_endpoint_auth_method != "none"
    end

    def token_endpoint_auth_method
      params[:token_endpoint_auth_method].presence || "client_secret_basic"
    end

    # Only keep scopes Campsite actually configures (Doorkeeper enforces this too),
    # falling back to a sensible default set so the connector works out of the box.
    def requested_scope_string
      requested_scopes.any? ? requested_scopes.join(" ") : DEFAULT_SCOPES
    end

    def requested_scopes
      @requested_scopes ||= params[:scope].to_s.split.uniq
    end

    def invalid_requested_scopes
      requested_scopes - Doorkeeper.config.scopes.all
    end

    def allowed_redirect_uri?(uri)
      parsed = URI.parse(uri)
      return false if parsed.scheme.blank?
      return false if FORBIDDEN_REDIRECT_SCHEMES.include?(parsed.scheme.downcase)

      true
    rescue URI::InvalidURIError
      false
    end

    def registration_response(application)
      response = {
        client_id: application.uid,
        client_id_issued_at: application.created_at.to_i,
        client_name: application.name,
        redirect_uris: application.redirect_uri.to_s.split,
        grant_types: ["authorization_code", "refresh_token"],
        response_types: ["code"],
        token_endpoint_auth_method: application.confidential? ? "client_secret_basic" : "none",
        scope: application.scopes.to_s,
      }
      # `plaintext_secret` is only readable immediately after creation because
      # application secrets are hashed at rest.
      response[:client_secret] = application.plaintext_secret if application.confidential?
      response
    end

    def render_registration_error(code, description)
      render(json: { error: code, error_description: description }, status: :bad_request)
    end
  end
end
