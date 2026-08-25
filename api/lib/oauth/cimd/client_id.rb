# frozen_string_literal: true

require "ipaddr"
require "uri"

module Oauth
  module Cimd
    class ClientId
      URL_SHAPED = /\Ahttps?:/i

      class << self
        def url_shaped?(value)
          value.to_s.match?(URL_SHAPED)
        end

        def parse!(value)
          raw = value.to_s
          uri = URI.parse(raw)

          raise InvalidClientId unless uri.is_a?(URI::HTTPS)
          raise InvalidClientId if uri.host.blank? || uri.userinfo.present?
          raise InvalidClientId if uri.fragment.present? || uri.query.present?
          raise InvalidClientId if uri.path.blank? || uri.path == "/"
          raise InvalidClientId if ip_literal?(uri.host)
          raise InvalidClientId if dot_segment?(uri.path)

          uri
        rescue URI::InvalidURIError
          raise InvalidClientId
        end

        private

        def dot_segment?(path)
          path.split("/").any? do |segment|
            decoded = URI::DEFAULT_PARSER.unescape(segment)
            decoded == "." || decoded == ".."
          end
        end

        def ip_literal?(host)
          IPAddr.new(host.delete_prefix("[").delete_suffix("]"))
          true
        rescue IPAddr::InvalidAddressError
          false
        end
      end
    end
  end
end
