# frozen_string_literal: true

require "minitest/autorun"
require "uri"

# This test runs both standalone (`ruby test/lib/campsite_configuration_test.rb`,
# where Rails is not loaded) and as part of the Rails suite. Only define the Rails
# stub in the standalone case — redefining `Rails.env` for real would break every
# test file loaded after this one.
REAL_RAILS = defined?(Rails) ? true : false

unless REAL_RAILS
  module Rails
    def self.env
      Environment.new
    end

    class Environment
      def production?
        true
      end
    end
  end
end

class CampsiteConfigurationTest < Minitest::Test
  URL_ENV_NAMES = %w[
    APP_URL
    STYLED_TEXT_API_URL
    HTML_TO_IMAGE_URL
    MARKETING_SITE_URL
    API_SUBDOMAIN
    ADMIN_SUBDOMAIN
  ].freeze

  def setup
    @original_env_values = URL_ENV_NAMES.index_with { |name| ENV[name] }

    return unless REAL_RAILS

    @original_rails_env = Rails.env
    Rails.env = "production"
  end

  def teardown
    @original_env_values.each do |name, value|
      value.nil? ? ENV.delete(name) : ENV[name] = value
    end

    Rails.env = @original_rails_env if REAL_RAILS && @original_rails_env

    # Restore the real Campsite constant for the rest of the suite.
    reload_campsite
  end

  def test_current_production_defaults_are_preserved
    load_campsite

    assert_equal("https://camp.polo-apps.com", Campsite.base_app_url.to_s)
    assert_equal("https://camp-styled-text.polo-apps.com", Campsite.base_styled_text_api_url.to_s)
    assert_equal("https://camp-html-to-image.polo-apps.com", Campsite.base_html_to_image_url.to_s)
    assert_equal("https://campsite.com", Campsite.base_marketing_site_url.to_s)
    assert_equal("api", Campsite.api_subdomain)
    assert_equal("admin", Campsite.admin_subdomain)
  end

  def test_tokdio_production_urls_and_subdomains_are_configurable
    load_campsite(
      "APP_URL" => "https://camp.tokdio.com",
      "STYLED_TEXT_API_URL" => "https://camp-styled-text.tokdio.com",
      "HTML_TO_IMAGE_URL" => "https://camp-html-to-image.tokdio.com",
      "MARKETING_SITE_URL" => "https://camp.tokdio.com",
      "API_SUBDOMAIN" => "camp-api",
      "ADMIN_SUBDOMAIN" => "camp-admin",
    )

    assert_equal("https://camp.tokdio.com", Campsite.base_app_url.to_s)
    assert_equal("https://camp-styled-text.tokdio.com", Campsite.base_styled_text_api_url.to_s)
    assert_equal("https://camp-html-to-image.tokdio.com", Campsite.base_html_to_image_url.to_s)
    assert_equal("https://camp.tokdio.com", Campsite.base_marketing_site_url.to_s)
    assert_equal("camp-api", Campsite.api_subdomain)
    assert_equal("camp-admin", Campsite.admin_subdomain)
  end

  def test_home_production_urls_use_https_for_browser_links_and_http_for_internal_services
    load_campsite(
      "APP_URL" => "https://camp.home",
      "STYLED_TEXT_API_URL" => "http://styled-text.camp.home",
      "HTML_TO_IMAGE_URL" => "http://html-to-image.camp.home",
      "MARKETING_SITE_URL" => "https://camp.home",
      "API_SUBDOMAIN" => "api",
      "ADMIN_SUBDOMAIN" => "admin",
    )

    assert_equal("https://camp.home", Campsite.base_app_url.to_s)
    assert_equal("http://styled-text.camp.home", Campsite.base_styled_text_api_url.to_s)
    assert_equal("http://html-to-image.camp.home", Campsite.base_html_to_image_url.to_s)
    assert_equal("api", Campsite.api_subdomain)
    assert_equal("admin", Campsite.admin_subdomain)
  end

  private

  def load_campsite(overrides = {})
    URL_ENV_NAMES.each { |name| ENV.delete(name) }
    overrides.each { |name, value| ENV[name] = value }
    reload_campsite
  end

  def reload_campsite
    Object.send(:remove_const, :Campsite) if Object.const_defined?(:Campsite)
    load File.expand_path("../../lib/campsite.rb", __dir__)
    load File.expand_path("../../lib/campsite/smtp_settings.rb", __dir__)
  end
end
