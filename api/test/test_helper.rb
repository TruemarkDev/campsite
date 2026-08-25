# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require_relative "support/assertions"
require_relative "support/action_mailer_test_helper"

require "rails/test_help"

# Rails 8.1 loads routes lazily on the first request. Devise populates
# `Devise.mappings` while drawing routes, but `sign_in` talks to Warden without
# issuing a request, so tests that authenticate before making any request would
# otherwise hit empty mappings ("Could not find a valid mapping for #<User ...>").
# Load routes once here, before parallel workers fork, so every worker inherits them.
Rails.application.reload_routes_unless_loaded

require "mocha/minitest"
require "vcr"

# `require "sidekiq/testing"` is deprecated (removed in Sidekiq 9). The new API is
# `Sidekiq.testing!(:fake)`, which loads the same Sidekiq::Testing helpers used below.
Sidekiq.testing!(:fake)

# flipper/test_help (auto-loaded in test env) reconfigures the default Flipper
# instance without an instrumenter, so it falls back to Noop and never emits the
# `feature_operation.flipper` notifications our FlipperAuditLog subscriber needs.
# Re-add the ActiveSupport::Notifications instrumenter; this persists across the
# per-test `flipper_reset` since that only nils the memoized instance.
Flipper.configure do |config|
  config.default { Flipper.new(config.adapter, instrumenter: ActiveSupport::Notifications) }
end

VCR.configure do |config|
  config.cassette_library_dir = "fixtures/vcr_cassettes"
  config.hook_into(:faraday)
  config.filter_sensitive_data("<LINEAR_TOKEN>") { Rails.application.credentials&.dig(:linear, :token) }
  config.filter_sensitive_data("<FIGMA_CLIENT_SECRET>") { Rails.application.credentials&.dig(:figma, :client_secret) }
  config.filter_sensitive_data("<FIGMA_OAUTH_TOKEN>") { Rails.application.credentials&.dig(:figma, :test_oauth_token) }
  config.filter_sensitive_data("<FIGMA_OAUTH_REFRESH_TOKEN>") { Rails.application.credentials&.dig(:figma, :test_oauth_refresh_token) }
  config.filter_sensitive_data("<PLAIN_API_KEY>") { Rails.application.credentials&.dig(:plain, :api_key) }
  config.filter_sensitive_data("<IMGIX_API_KEY>") { Rails.application.credentials&.dig(:imgix, :api_key) }
  config.filter_sensitive_data("<IMGIX_SOURCE_ID>") { Rails.application.credentials&.dig(:imgix, :source_id) }
  config.filter_sensitive_data("<OPENAI_API_KEY>") { Rails.application.credentials&.dig(:openai, :access_token) }
  config.filter_sensitive_data("<OPENAI_ORGANIZATION>") { Rails.application.credentials&.dig(:openai, :organization_id) }
  config.filter_sensitive_data("<TENOR_API_KEY>") { Rails.application.credentials&.dig(:tenor, :api_key) }
  # Derived from ELASTICSEARCH_URL rather than hardcoded: searchkick talks to
  # whatever that env var points at, and a mismatch here makes VCR reject every
  # elasticsearch call in the suite (a service container named `elasticsearch`,
  # or simply a non-default port, would otherwise fail every test).
  elasticsearch_uri = URI(ENV.fetch("ELASTICSEARCH_URL", "http://localhost:9200"))

  config.ignore_request do |request|
    uri = URI(request.uri)
    # ignore elasticsearch requests
    uri.host == elasticsearch_uri.host && uri.port == elasticsearch_uri.port
  end
end

def reindex_models
  Post.reindex
  Call.reindex
  Note.reindex
  Searchkick.disable_callbacks
end

# if were not running parallel tests, reindex immediately
if ENV["PARALLEL_WORKERS"] == "1"
  reindex_models
end

module ActiveSupport
  class TestCase
    include FactoryBot::Syntax::Methods
    include ActionMailer::TestHelper

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    parallelize_setup do |worker|
      # https://github.com/ankane/searchkick#parallel-tests
      Searchkick.index_suffix = worker

      # reindex models
      reindex_models
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    # fixtures :all

    OmniAuth.config.test_mode = true

    setup do
      ActionMailer::Base.deliveries.clear
      Pusher.stubs(:trigger)
      ActiveJob::Base.disable_test_adapter
    end

    teardown do
      Sidekiq::Worker.clear_all
      Rails.cache.clear
    end

    def json_response
      ::JSON.parse(response.body)
    end

    def otp_attempt(secret)
      ROTP::TOTP.new(secret).at(Time.current)
    end

    def desktop_user_agent
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Campsite/1.0.0 Chrome/106.0.5249.199 Safari/537.36"
    end

    def assert_query_count(expected_count, verbose = false, &block)
      queries = []

      count_method = lambda { |_name, _started, _finished, _unique_id, payload|
        if ["CACHE", "SCHEMA"].exclude?(payload[:name]) && !payload[:cached]
          queries << payload[:sql]
        end
      }

      ActiveSupport::Notifications.subscribed(
        count_method,
        "sql.active_record",
        &block
      )

      if verbose
        queries_text = queries.join("\n")
        assert_equal(expected_count, queries.length, "Expected #{expected_count} SQL queries, but got #{queries.length}. Queries:\n#{queries_text}")
      else
        assert_equal(expected_count, queries.length, "Expected #{expected_count} SQL queries, but got #{queries.length}")
      end
    end
  end
end
