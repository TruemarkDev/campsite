# frozen_string_literal: true

require "minitest/autorun"

require_relative "../../lib/campsite/smtp_settings"

class SmtpSettingsTest < Minitest::Test
  def test_preserves_authenticated_postmark_defaults
    settings = Campsite::SmtpSettings.build(
      environment: {},
      credentials: { smtp: { user: "postmark-user", password: "postmark-password" } },
    )

    assert_equal(
      {
        address: "smtp.postmarkapp.com",
        port: 587,
        domain: "tokdio.com",
        enable_starttls_auto: true,
        user_name: "postmark-user",
        password: "postmark-password",
        authentication: "plain",
      },
      settings,
    )
  end

  def test_omits_all_credentials_for_an_unauthenticated_internal_relay
    settings = Campsite::SmtpSettings.build(
      environment: {
        "SMTP_ADDRESS" => "smtp.home",
        "SMTP_PORT" => "25",
        "SMTP_DOMAIN" => "agents.home",
        "SMTP_AUTHENTICATION" => "none",
        "SMTP_STARTTLS" => "false",
      },
      credentials: { smtp: { user: "must-not-leak", password: "must-not-leak" } },
    )

    assert_equal(
      {
        address: "smtp.home",
        port: 25,
        domain: "agents.home",
        enable_starttls_auto: false,
      },
      settings,
    )
    assert_empty(settings.keys & %i[authentication user_name password])
  end

  def test_rejects_unknown_authentication
    error = assert_raises(ArgumentError) do
      Campsite::SmtpSettings.build(environment: { "SMTP_AUTHENTICATION" => "disabled" })
    end

    assert_match(/SMTP_AUTHENTICATION/, error.message)
  end

  def test_rejects_ambiguous_starttls_values
    error = assert_raises(ArgumentError) do
      Campsite::SmtpSettings.build(environment: { "SMTP_STARTTLS" => "no" })
    end

    assert_match(/SMTP_STARTTLS/, error.message)
  end
end
