# frozen_string_literal: true

module Integrations
  class AuthsController < ApplicationController
    AUTHORIZATION_ENDPOINTS = {
      "linear.app" => ["/oauth/authorize"],
      "slack.com" => ["/oauth/authorize", "/oauth/v2/authorize"],
      "www.figma.com" => ["/oauth"],
    }.freeze

    before_action :validate_auth_url, only: :new

    def new
      store_integration_auth_params(auth_params)
      store_integration_auth_state(Rack::Utils.parse_query(@auth_url.query)["state"])
      redirect_to(@auth_url.to_s, allow_other_host: true)
    end

    private

    def auth_params
      params.slice(:success_path, :desktop_app, :enable_notifications).permit!
    end

    def validate_auth_url
      @auth_url = URI.parse(params[:auth_url])
      raise URI::InvalidURIError unless allowed_auth_url?(@auth_url)
    rescue URI::InvalidURIError, TypeError
      @error_message = "Invalid auth url"
      render("errors/show", status: :bad_request)
    end

    def allowed_auth_url?(uri)
      return false unless uri.is_a?(URI::HTTPS)
      return false if uri.host.blank? || uri.userinfo.present? || uri.port != 443 || uri.fragment.present?

      AUTHORIZATION_ENDPOINTS.fetch(uri.host.downcase, []).include?(uri.path)
    end
  end
end
