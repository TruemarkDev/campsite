# frozen_string_literal: true

require "test_helper"

module Oauth
  module Cimd
    class ResolverTest < ActiveSupport::TestCase
      CLIENT_ID = "https://client.example/oauth/metadata.json"
      DOCUMENT = JSON.generate({
        client_id: CLIENT_ID,
        client_name: "Example Client",
        redirect_uris: ["https://client.example/oauth/callback"],
      })

      test "persists a controlled public application and reuses valid cached metadata" do
        response = Fetcher::Response.new(body: DOCUMENT, headers: { "cache-control" => ["max-age=300"] })
        fetcher = mock
        fetcher.expects(:fetch!).once.returns(response)
        cache = ActiveSupport::Cache::MemoryStore.new
        resolver = Resolver.new(cache: cache, fetcher: fetcher)

        first = resolver.resolve!(CLIENT_ID)
        second = resolver.resolve!(CLIENT_ID)

        assert_equal first, second
        assert_predicate first, :mcp_cimd?
        assert_not_predicate first, :confidential?
        assert_equal "Example Client", first.name
        assert_equal "https://client.example/oauth/callback", first.redirect_uri
      end

      test "does not cache invalid metadata" do
        response = Fetcher::Response.new(body: "{}", headers: { "cache-control" => ["max-age=300"] })
        fetcher = mock
        fetcher.expects(:fetch!).twice.returns(response)
        resolver = Resolver.new(cache: ActiveSupport::Cache::MemoryStore.new, fetcher: fetcher)

        2.times do
          assert_raises(InvalidMetadata) { resolver.resolve!(CLIENT_ID) }
        end
      end

      test "refetches expired metadata and never falls back to a stale document" do
        response = Fetcher::Response.new(body: DOCUMENT, headers: { "cache-control" => ["max-age=1"] })
        calls = 0
        fetcher = Object.new
        fetcher.define_singleton_method(:fetch!) do |_uri|
          calls += 1
          raise FetchError if calls > 1

          response
        end
        resolver = Resolver.new(cache: ActiveSupport::Cache::MemoryStore.new, fetcher: fetcher)

        resolver.resolve!(CLIENT_ID)
        travel 61.seconds do
          assert_raises(FetchError) { resolver.resolve!(CLIENT_ID) }
        end

        assert_equal 2, calls
      end
    end
  end
end
