# frozen_string_literal: true

require "test_helper"

class RankedPaginationTest < ActiveSupport::TestCase
  test "hydrates only returned records and retains relevance order across pages" do
    users = create_list(:user, 4)
    scope = User.in_order_of(:id, [users[2].id, users[0].id, users[3].id, users[1].id])
    hydrated = 0
    subscriber = ->(_name, _start, _finish, _id, payload) { hydrated += payload[:record_count] if payload[:class_name] == "User" }
    page = nil
    ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
      page = RankedPagination.new(scope: scope, hydration_scope: User.all, limit: 2).run
    end
    assert_equal 2, hydrated
    assert_equal [users[2], users[0]], page.results
    assert_equal users[0].public_id, page.next_cursor

    page = RankedPagination.new(scope: scope, hydration_scope: User.all, limit: 2, after: page.next_cursor).run
    assert_equal [users[3], users[1]], page.results
    assert_nil page.next_cursor
  end

  test "default and oversized windows bound hydration" do
    User.insert_all!(Array.new(105) { |index| { public_id: "rank#{index}", email: "rank#{index}@example.com" } })
    scope = User.order(:id)
    [nil, 0, -1, "invalid", 10_000].each do |limit|
      expected = limit == 10_000 ? 100 : 50
      hydrated = 0
      subscriber = ->(_name, _start, _finish, _id, payload) { hydrated += payload[:record_count] if payload[:class_name] == "User" }
      ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
        page = RankedPagination.new(scope: scope, hydration_scope: User.all, limit: limit).run
        assert_equal expected, page.results.length
        assert_equal page.results.last.public_id, page.next_cursor
      end
      assert_equal expected, hydrated
    end
  end

  test "an unknown or unauthorized cursor does not restart the first page" do
    user = create(:user)
    page = RankedPagination.new(scope: User.where(id: user.id), hydration_scope: User.all, after: "missing").run
    assert_empty page.results
    assert_nil page.next_cursor
  end
end
