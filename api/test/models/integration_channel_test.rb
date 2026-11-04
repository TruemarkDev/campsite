# frozen_string_literal: true

require "test_helper"

class IntegrationChannelTest < ActiveSupport::TestCase
  test "search_name matches channel name text" do
    channel = create(:integration_channel, name: "Engineering Updates")

    assert_includes IntegrationChannel.search_name("Engineering"), channel
    assert_empty IntegrationChannel.search_name("Missing")
  end
end
