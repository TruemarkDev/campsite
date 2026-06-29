# frozen_string_literal: true

# RubyLLM Configuration
# https://rubyllm.com/configuration/

RubyLLM.configure do |config|
  # Opt into the new acts_as API (the legacy one is deprecated and removed in RubyLLM 2.0).
  # We don't use the ActiveRecord integration (acts_as_chat/message/...), so this only
  # silences the deprecation warning with no behavioral change.
  config.use_new_acts_as = true

  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY", Rails.application.credentials.dig(:gemini, :api_key))
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", Rails.application.credentials.dig(:openai, :api_key))
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", Rails.application.credentials.dig(:anthropic, :api_key))

  config.default_model = "gemini-2.5-flash"
  config.default_embedding_model = "text-embedding-004"
  config.request_timeout = 120
  config.max_retries = 3

  config.logger = Rails.logger
  config.log_level = Rails.env.production? ? :info : :debug
  if Rails.env.development?
    config.request_timeout = 60
  end
  if Rails.env.test?
    config.request_timeout = 30
    config.max_retries = 1
  end
end
