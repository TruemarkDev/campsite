# frozen_string_literal: true

require "test_helper"

module Oauth
  module Cimd
    class MetadataTest < ActiveSupport::TestCase
      CLIENT_ID = "https://client.example/oauth/metadata.json"

      test "parses required metadata and ignores optional URLs" do
        metadata = Metadata.parse!(
          JSON.generate({
            client_id: CLIENT_ID,
            client_name: "Example Client",
            redirect_uris: ["https://client.example/oauth/callback"],
            logo_uri: "http://127.0.0.1/logo.png",
          }),
          expected_client_id: CLIENT_ID,
        )

        assert_equal "Example Client", metadata.client_name
        assert_equal ["https://client.example/oauth/callback"], metadata.redirect_uris
      end

      test "rejects malformed documents, mismatches, and invalid redirects" do
        invalid_documents = [
          "{",
          "[]",
          JSON.generate({ client_id: CLIENT_ID, client_name: "Example Client" }),
          JSON.generate({ client_id: "https://other.example/client.json", client_name: "Example Client", redirect_uris: ["https://client.example/callback"] }),
          JSON.generate({ client_id: CLIENT_ID, client_name: "Example Client", redirect_uris: ["javascript:alert(1)"] }),
        ]

        invalid_documents.each do |document|
          assert_raises(InvalidMetadata) { Metadata.parse!(document, expected_client_id: CLIENT_ID) }
        end
      end
    end
  end
end
