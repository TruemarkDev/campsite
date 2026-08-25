# frozen_string_literal: true

require "test_helper"

module Oauth
  class AuthorizationResponseTest < ActiveSupport::TestCase
    test "adds the issuer to body and query redirect responses" do
      original = stub(
        body: { code: "code", state: "state" },
        redirect_uri: "https://client.example/callback?code=code&state=state",
      )
      response = AuthorizationResponse.new(original, issuer: "https://auth.example")

      assert_equal "https://auth.example", response.body[:iss]
      assert_equal "https://auth.example", Rack::Utils.parse_query(URI(response.redirect_uri).query)["iss"]
    end

    test "adds the issuer to fragment responses" do
      original = stub(body: { code: "code" }, redirect_uri: "https://client.example/callback#code=code")
      response = AuthorizationResponse.new(original, issuer: "https://auth.example")

      assert_equal "https://auth.example", Rack::Utils.parse_query(URI(response.redirect_uri).fragment)["iss"]
    end
  end
end
