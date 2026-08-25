# frozen_string_literal: true

module Oauth
  module Cimd
    CACHE_NAMESPACE = "oauth:cimd:metadata:v1"
    DEFAULT_CACHE_TTL = 5.minutes
    MIN_CACHE_TTL = 1.minute
    MAX_CACHE_TTL = 1.hour
    DEFAULT_SCOPES = "mcp read_organization read_user read_post read_project write_post write_message"
    FEATURE_NAME = :mcp_cimd_registration

    class Error < StandardError; end
    class InvalidClientId < Error; end
    class FetchError < Error; end
    class PolicyError < FetchError; end
    class InvalidMetadata < Error; end

    def self.enabled?
      feature = Flipper.feature(FEATURE_NAME)
      feature.exist? && feature.enabled?
    end

    def self.instrument(outcome, host: nil)
      Rails.event.notify("campsite.oauth.cimd.resolve", outcome: outcome, host: host)
    end
  end
end
