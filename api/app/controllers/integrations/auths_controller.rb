# frozen_string_literal: true

module Integrations
  class AuthsController < ApplicationController
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
      raise URI::InvalidURIError unless @auth_url.is_a?(URI::HTTP) && @auth_url.host.present? && @auth_url.userinfo.nil?
    rescue URI::InvalidURIError, TypeError
      @error_message = "Invalid auth url"
      render("errors/show", status: :bad_request)
    end
  end
end
