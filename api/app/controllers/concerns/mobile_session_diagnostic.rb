# frozen_string_literal: true

require "digest"

module MobileSessionDiagnostic
  extend ActiveSupport::Concern

  SESSION_COOKIE_NAME = "_campsite_api_session"
  DIAGNOSTIC_PATHS = ["/sign-in", "/v1/users/me"].freeze

  included do
    before_action :log_mobile_session_diagnostic
  end

  class_methods do
    def mobile_session_cookie_metadata(raw_cookie)
      raw_cookie.to_s.split(";").filter_map do |pair|
        name, value = pair.strip.split("=", 2)
        next unless name == SESSION_COOKIE_NAME

        value = value.to_s
        {
          length: value.bytesize,
          fingerprint: Digest::SHA256.hexdigest(value)[0, 16],
        }
      end
    end
  end

  private

  def log_mobile_session_diagnostic
    return unless DIAGNOSTIC_PATHS.include?(request.path)
    return unless request.user_agent.to_s.match?(/iPhone|iPad|CriOS/)

    raw_cookie = request.get_header("HTTP_COOKIE").to_s
    session_cookies = self.class.mobile_session_cookie_metadata(raw_cookie)

    Rails.logger.info({
      event: "mobile_session_diagnostic",
      host: request.host,
      path: request.path,
      method: request.request_method,
      origin: request.headers["Origin"],
      sec_fetch_site: request.headers["Sec-Fetch-Site"],
      sec_fetch_mode: request.headers["Sec-Fetch-Mode"],
      sec_fetch_dest: request.headers["Sec-Fetch-Dest"],
      cookie_header_present: raw_cookie.present?,
      cookie_header_length: raw_cookie.bytesize,
      session_cookie_count: session_cookies.length,
      session_cookies: session_cookies,
      signed_in: user_signed_in?,
    }.to_json)
  end
end
