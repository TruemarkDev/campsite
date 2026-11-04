# frozen_string_literal: true

require "test_helper"

class IntegrationTeamTest < ActiveSupport::TestCase
  test "search_name matches team name text" do
    team = create(:integration_team, name: "Engineering Team")

    assert_includes IntegrationTeam.search_name("Engineering"), team
    assert_empty IntegrationTeam.search_name("Missing")
  end
end
