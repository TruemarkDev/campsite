# frozen_string_literal: true

require "delegate"
require "uri"

module Oauth
  class AuthorizationResponse < SimpleDelegator
    def initialize(response, issuer:)
      super(response)
      @issuer = issuer
    end

    def body
      __getobj__.body.merge(iss: @issuer)
    end

    def redirect_uri
      original = __getobj__.redirect_uri
      return original unless original.is_a?(String)

      uri = URI.parse(original)
      if uri.fragment.present?
        uri.fragment = append_issuer(uri.fragment)
      else
        uri.query = append_issuer(uri.query)
      end
      uri.to_s
    end

    private

    def append_issuer(parameters)
      values = URI.decode_www_form(parameters.to_s)
      values.reject! { |key, _value| key == "iss" }
      values << ["iss", @issuer]
      URI.encode_www_form(values)
    end
  end
end
