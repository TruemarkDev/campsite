# frozen_string_literal: true

require "minitest/autorun"
require "uri"

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

class CampsiteConfigurationTest < Minitest::Test
  URL_ENV_NAMES = %w[
    APP_URL
    STYLED_TEXT_API_URL
    HTML_TO_IMAGE_URL
    MARKETING_SITE_URL
    API_SUBDOMAIN
    ADMIN_SUBDOMAIN
  ].freeze

  def teardown
    URL_ENV_NAMES.each { |name| ENV.delete(name) }
    Object.send(:remove_const, :Campsite) if Object.const_defined?(:Campsite)
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

  private

  def load_campsite(overrides = {})
    URL_ENV_NAMES.each { |name| ENV.delete(name) }
    overrides.each { |name, value| ENV[name] = value }
    Object.send(:remove_const, :Campsite) if Object.const_defined?(:Campsite)
    load File.expand_path("../../lib/campsite.rb", __dir__)
  end
end
