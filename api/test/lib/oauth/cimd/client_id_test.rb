# frozen_string_literal: true

require "test_helper"

module Oauth
  module Cimd
    class ClientIdTest < ActiveSupport::TestCase
      test "accepts a public HTTPS URL with a non-root path" do
        uri = ClientId.parse!("https://client.example/oauth/metadata.json")

        assert_equal "client.example", uri.host
        assert_not ClientId.url_shaped?("urn:ietf:wg:oauth:2.0:oob")
      end

      test "rejects unsafe or unstable client IDs" do
        invalid_ids = [
          "http://client.example/metadata.json",
          "https://client.example/",
          "https://user@client.example/metadata.json",
          "https://client.example/metadata.json?token=secret",
          "https://client.example/metadata.json#fragment",
          "https://client.example/oauth/../metadata.json",
          "https://127.0.0.1/metadata.json",
          "not-a-url",
        ]

        invalid_ids.each do |client_id|
          assert_raises(InvalidClientId, client_id) { ClientId.parse!(client_id) }
        end
      end
    end
  end
end
