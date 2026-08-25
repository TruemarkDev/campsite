# frozen_string_literal: true

require "test_helper"

module Oauth
  class CimdTest < ActiveSupport::TestCase
    test "reports resolution outcomes as structured events" do
      assert_event_reported(
        "campsite.oauth.cimd.resolve",
        payload: { outcome: :success, host: "client.example" },
      ) do
        Cimd.instrument(:success, host: "client.example")
      end
    end
  end
end
