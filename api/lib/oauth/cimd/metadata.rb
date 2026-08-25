# frozen_string_literal: true

require "json"
require "uri"

module Oauth
  module Cimd
    class Metadata
      attr_reader :client_id, :client_name, :redirect_uris

      def self.parse!(json, expected_client_id:)
        document = JSON.parse(json)
        raise InvalidMetadata unless document.is_a?(Hash)

        new(document, expected_client_id: expected_client_id)
      rescue JSON::ParserError
        raise InvalidMetadata
      end

      def initialize(document, expected_client_id:)
        @client_id = required_string(document, "client_id")
        @client_name = required_string(document, "client_name")
        @redirect_uris = document["redirect_uris"]

        raise InvalidMetadata unless client_id == expected_client_id
        raise InvalidMetadata if client_name.length > 255
        raise InvalidMetadata unless redirect_uris.is_a?(Array) && redirect_uris.any?
        raise InvalidMetadata unless redirect_uris.all? { |uri| valid_redirect_uri?(uri) }
      end

      def to_cache
        { "client_id" => client_id, "client_name" => client_name, "redirect_uris" => redirect_uris }
      end

      private

      def required_string(document, key)
        value = document[key]
        raise InvalidMetadata unless value.is_a?(String) && value.present?

        value
      end

      def valid_redirect_uri?(value)
        return false unless value.is_a?(String) && value.present?

        uri = URI.parse(value)
        return false unless uri.absolute? && uri.host.present? && uri.fragment.nil?

        Doorkeeper::OAuth::Helpers::URIChecker.valid_for_authorization?(value, value)
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
