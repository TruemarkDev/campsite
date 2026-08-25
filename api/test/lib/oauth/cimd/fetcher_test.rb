# frozen_string_literal: true

require "test_helper"

module Oauth
  module Cimd
    class FetcherTest < ActiveSupport::TestCase
      class StubResponse < Net::HTTPOK
        def initialize(body:, content_type: "application/json")
          super("1.1", "200", "OK")
          self["Content-Type"] = content_type
          @stub_body = body
        end

        def read_body
          yield @stub_body
        end
      end

      class RedirectResponse < Net::HTTPFound
        def initialize
          super("1.1", "302", "Found")
        end

        def read_body
          yield ""
        end
      end

      class StubConnection
        def initialize(response)
          @response = response
        end

        def request(_request)
          yield @response
          @response
        end
      end

      class TimeoutConnection
        def request(_request)
          raise Timeout::Error
        end
      end

      test "pins a public DNS answer and reads a JSON response" do
        response = StubResponse.new(body: "{\"client_id\":\"value\"}")
        pinned_address = nil
        fetcher = Fetcher.new(
          resolver: ->(_host) { ["93.184.216.34"] },
          connection_factory: lambda do |_uri, address|
            pinned_address = address
            StubConnection.new(response)
          end,
        )

        result = fetcher.fetch!(URI("https://client.example/metadata.json"))

        assert_equal "93.184.216.34", pinned_address
        assert_equal "{\"client_id\":\"value\"}", result.body
      end

      test "rejects any DNS set containing a special-use address before connecting" do
        connected = false
        fetcher = Fetcher.new(
          resolver: ->(_host) { ["93.184.216.34", "127.0.0.1"] },
          connection_factory: ->(_uri, _address) { connected = true },
        )

        assert_raises(FetchError) { fetcher.fetch!(URI("https://client.example/metadata.json")) }
        assert_not connected
      end

      test "rejects current special-purpose IPv4 and IPv6 ranges" do
        ["192.31.196.1", "100:0:0:1::1", "3fff::1", "5f00::1"].each do |address|
          fetcher = Fetcher.new(
            resolver: ->(_host) { [address] },
            connection_factory: ->(_uri, _address) { flunk("must not connect to #{address}") },
          )

          assert_raises(PolicyError) { fetcher.fetch!(URI("https://client.example/metadata.json")) }
        end
      end

      test "rejects redirects, non-JSON content, and oversized bodies" do
        responses = [
          RedirectResponse.new,
          StubResponse.new(body: "{}", content_type: "text/html"),
          StubResponse.new(body: "x" * (Fetcher::MAX_BODY_BYTES + 1)),
        ]

        responses.each do |response|
          fetcher = Fetcher.new(
            resolver: ->(_host) { ["93.184.216.34"] },
            connection_factory: ->(_uri, _address) { StubConnection.new(response) },
          )

          assert_raises(FetchError) { fetcher.fetch!(URI("https://client.example/metadata.json")) }
        end
      end

      test "turns connection timeouts into a closed fetch failure" do
        fetcher = Fetcher.new(
          resolver: ->(_host) { ["93.184.216.34"] },
          connection_factory: ->(_uri, _address) { TimeoutConnection.new },
        )

        assert_raises(FetchError) { fetcher.fetch!(URI("https://client.example/metadata.json")) }
      end
    end
  end
end
