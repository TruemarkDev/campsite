# frozen_string_literal: true

require "time"

module Oauth
  module Cimd
    class CachePolicy
      def self.ttl(headers, now: Time.current)
        new(headers, now: now).ttl
      end

      def initialize(headers, now:)
        @headers = headers
        @now = now
      end

      def ttl
        return if directives.any? { |directive| directive.start_with?("no-store", "no-cache", "private") }

        seconds = cache_control_ttl || expires_ttl || DEFAULT_CACHE_TTL.to_i
        return if seconds <= 0

        seconds.clamp(MIN_CACHE_TTL.to_i, MAX_CACHE_TTL.to_i).seconds
      end

      private

      attr_reader :headers, :now

      def directives
        @directives ||= Array(headers["cache-control"]).flat_map { |value| value.downcase.split(",") }.map(&:strip)
      end

      def cache_control_ttl
        directive = ["s-maxage", "max-age"].filter_map do |name|
          directives.find { |value| value.match?(/\A#{name}=\d+\z/) }
        end.first
        return unless directive

        directive.split("=", 2).last.to_i - age
      end

      def expires_ttl
        value = Array(headers["expires"]).first
        return unless value

        Time.httpdate(value).to_i - response_date.to_i - age
      rescue ArgumentError
        nil
      end

      def response_date
        value = Array(headers["date"]).first
        value ? Time.httpdate(value) : now
      rescue ArgumentError
        now
      end

      def age
        Array(headers["age"]).first.to_i.clamp(0, MAX_CACHE_TTL.to_i)
      end
    end
  end
end
