# frozen_string_literal: true

Rails.application.config.session_store(
  :cookie_store,
  key: "_campsite_api_session",
  domain: :all,
  same_site: :lax,
  expire_after: 24.hours,
  httponly: true,
  secure: ENV.fetch("SESSION_COOKIE_SECURE", Rails.env.production?.to_s) == "true",
)
