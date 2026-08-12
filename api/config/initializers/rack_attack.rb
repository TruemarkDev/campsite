# frozen_string_literal: true

require "digest"

module Rack
  class Attack
    REQUESTS_BY_IP_LIMIT = 500
    REQUESTS_BY_IP_PERIOD = 30.seconds

    MCP_WRITE_REQUESTS_LIMIT = 30
    MCP_GENERAL_REQUESTS_LIMIT = 120
    MCP_REQUESTS_PERIOD = 1.minute
    MCP_WRITE_TOOL_NAMES = [
      "add_comment",
      "add_reaction",
      "attach_file",
      "create_follow_up",
      "create_message_thread",
      "create_note",
      "create_post",
      "create_project",
      "create_upload",
      "mark_notification_read",
      "reply_to_comment",
      "resolve_post",
      "send_message",
      "update_note",
      "update_post",
      "upload_attachment",
    ].to_set.freeze

    MCP_REQUEST_DISCRIMINATOR = lambda do |request|
      authorization = request.get_header("HTTP_AUTHORIZATION").to_s
      bearer_token = authorization[/\ABearer\s+(.+)\z/i, 1]

      if bearer_token.present?
        "token:#{Digest::SHA256.hexdigest(bearer_token)}"
      else
        "ip:#{request.env["HTTP_FLY_CLIENT_IP"].presence || request.ip}"
      end
    end
  end
end

Rack::Attack.enabled = false

if Rails.env.production?
  Rack::Attack.enabled = true
  Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
    url: ENV["RACK_ATTACK_REDIS_URL"] || ENV["REDIS_URL"] || Rails.application.credentials&.rack_attack&.url,
  )
end

Rack::Attack.blocklist_ip("46.246.41.169")

Rack::Attack.safelist("mark server-side rendering requests safe") do |request|
  request.get_header("HTTP_X_CAMPSITE_SSR_SECRET") == Rails.application.credentials.rack_attack.fetch(:ssr_secret)
end

HIGH_RATE_PATHS = [
  "/v1/integrations/slack/events",
  "/v1/product_logs",
].to_set.freeze

Rack::Attack.throttle("requests by ip", limit: Rack::Attack::REQUESTS_BY_IP_LIMIT, period: Rack::Attack::REQUESTS_BY_IP_PERIOD) do |req|
  "ip:#{req.env["HTTP_FLY_CLIENT_IP"]}" unless HIGH_RATE_PATHS.include?(req.path)
end

Rack::Attack.throttle("integration requests by ip", limit: 10000, period: 30.seconds) do |req|
  "ip:#{req.env["HTTP_FLY_CLIENT_IP"]}" if HIGH_RATE_PATHS.include?(req.path)
end

# Throttle login attempts for a given email parameter to 6 reqs/minute
# Return the *normalized* email as a discriminator on POST /login requests
Rack::Attack.throttle("limit logins per email", limit: 6, period: 60) do |req|
  if req.path == "/sign-in" && req.post?
    # Normalize the email, using the same logic as your authentication process, to
    # protect against rate limit bypasses.
    req.params.dig("user", "email").to_s.downcase.gsub(/\s+/, "")
  end
end

# Throttle login attempts for a given email parameter to 2 reqs/minute
# Return the *normalized* email as a discriminator on POST /password requests
Rack::Attack.throttle("limit password reset requests per email", limit: 2, period: 60) do |req|
  if req.path == "/password" && req.post?
    # Normalize the email, using the same logic as your authentication process, to
    # protect against rate limit bypasses.
    req.params.dig("user", "email").to_s.downcase.gsub(/\s+/, "")
  end
end

# Throttle sign up attempts for an ip to 6 reqs/minute
Rack::Attack.throttle("limit sign ups per email", limit: 6, period: 60) do |req|
  if req.path == "/" && req.host&.split(".")&.first == "auth" && req.post?
    "ip:#{req.env["HTTP_FLY_CLIENT_IP"]}"
  end
end

# Throttle MCP dynamic client registration to cap OauthApplication row spam from
# anonymous clients (RFC 7591 registration is open by design — see Decision 6).
Rack::Attack.throttle("limit mcp dynamic client registration per ip", limit: 5, period: 60) do |req|
  "ip:#{req.env["HTTP_FLY_CLIENT_IP"]}" if req.path == "/oauth/register" && req.post?
end

Rack::Attack.throttle(
  "limit mcp write requests per token or ip",
  limit: Rack::Attack::MCP_WRITE_REQUESTS_LIMIT,
  period: Rack::Attack::MCP_REQUESTS_PERIOD,
) do |req|
  if req.path == "/mcp" && req.post? && Rack::Attack::MCP_WRITE_TOOL_NAMES.include?(req.get_header("HTTP_MCP_NAME"))
    Rack::Attack::MCP_REQUEST_DISCRIMINATOR.call(req)
  end
end

Rack::Attack.throttle(
  "limit mcp general requests per token or ip",
  limit: Rack::Attack::MCP_GENERAL_REQUESTS_LIMIT,
  period: Rack::Attack::MCP_REQUESTS_PERIOD,
) do |req|
  if req.path == "/mcp" && req.post? && Rack::Attack::MCP_WRITE_TOOL_NAMES.exclude?(req.get_header("HTTP_MCP_NAME"))
    Rack::Attack::MCP_REQUEST_DISCRIMINATOR.call(req)
  end
end

ActiveSupport::Notifications.subscribe(/rack_attack/) do |_name, _start, _finish, _request_id, payload|
  req = payload[:request]

  if [:throttle, :blocklist].include?(req.env["rack.attack.match_type"])
    Rails.logger.info("[Rack::Attack][Blocked] " \
      "HTTP_FLY_CLIENT_IP: \"#{req.env["HTTP_FLY_CLIENT_IP"]}\", " \
      "path: \"#{req.fullpath}\" " \
      "user: \"#{req.env["warden"].user&.username}\"")
  end
end
