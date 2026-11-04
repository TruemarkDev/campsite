# frozen_string_literal: true

# Used only by the disposable fixture stack, never by deployed services.
if ENV["CAMPSITE_BROWSER_TEST"] == "1"
  raise "Browser fixtures require the test environment" unless Rails.env.test?
  raise "Unsafe browser fixture database" unless ENV.fetch("PG_TEST_DATABASE").match?(/\Acampsite_browser_[a-f0-9]{16}\z/)

  require "webmock"
  WebMock.enable!
  WebMock.disable_net_connect!(allow_localhost: true)
  Sidekiq.testing!(:fake)
  Rails.application.credentials.styled_text_api.authtoken = ENV.fetch("BROWSER_STYLED_TEXT_TOKEN")
  if ENV["BROWSER_TEST_SERVER"] == "1"
    Rails.application.config.after_initialize { Flipper.enable(:ai_note_editing) }
  end
end
