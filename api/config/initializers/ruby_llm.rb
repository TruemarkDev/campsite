# frozen_string_literal: true

# RubyLLM Configuration
# https://rubyllm.com/configuration/

RubyLLM.configure do |config|
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY", Rails.application.credentials.dig(:gemini, :api_key))

  config.default_model = "gemini-2.5-flash"
  config.default_embedding_model = "gemini-embedding-001"
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

    # Llm#initialize refuses to build a client when no provider is configured,
    # so jobs that stub Llm#chat could not even construct one. The suite never
    # reaches the network (calls are stubbed or recorded by VCR), so a
    # placeholder key is enough to let construction succeed.
    config.gemini_api_key ||= "test-gemini-api-key"
  end
end
