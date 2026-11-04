# frozen_string_literal: true

require "test_helper"
require "erb"
require "yaml"

class DatabaseConnectionBudgetTest < ActiveSupport::TestCase
  def pool_for(overrides)
    names = %w[DB_POOL RAILS_MAX_THREADS RAILS_MAX_ASYNC_QUERIES SIDEKIQ_CONCURRENCY]
    previous = names.index_with { |name| ENV[name] }
    names.each { |name| ENV.delete(name) }
    ENV.update(overrides)
    YAML.safe_load(ERB.new(Rails.root.join("config/database.yml").read).result, aliases: true).dig("test", "primary", "pool")
  ensure
    previous.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
  end

  test "default capacity covers five foreground threads, four async threads and headroom" do
    assert_equal 10, pool_for({})
  end

  test "foreground and async overrides size the pool additively" do
    assert_equal 25, pool_for("SIDEKIQ_CONCURRENCY" => "20")
    assert_equal 14, pool_for("RAILS_MAX_ASYNC_QUERIES" => "8")
    assert_equal 17, pool_for("DB_POOL" => "17")
  end

  test "invalid thread settings fail instead of silently producing a zero pool" do
    assert_raises(ArgumentError) { pool_for("RAILS_MAX_ASYNC_QUERIES" => "invalid") }
  end
end
