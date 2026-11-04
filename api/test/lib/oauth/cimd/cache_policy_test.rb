# frozen_string_literal: true

require "test_helper"

module Oauth
  module Cimd
    class CachePolicyTest < ActiveSupport::TestCase
      test "does not cache responses that require revalidation" do
        assert_nil CachePolicy.ttl({ "cache-control" => ["no-store"] })
        assert_nil CachePolicy.ttl({ "cache-control" => ["no-cache=\"set-cookie\""] })
        assert_nil CachePolicy.ttl({ "cache-control" => ["private, max-age=300"] })
        assert_nil CachePolicy.ttl({ "cache-control" => ["max-age=0"] })
      end

      test "clamps positive cache freshness to deployment bounds" do
        assert_equal 1.minute, CachePolicy.ttl({ "cache-control" => ["max-age=1"] })
        assert_equal 1.hour, CachePolicy.ttl({ "cache-control" => ["max-age=30, s-maxage=86400"] })
      end

      test "uses a bounded default when freshness is absent" do
        assert_equal 5.minutes, CachePolicy.ttl({})
      end
    end
  end
end
