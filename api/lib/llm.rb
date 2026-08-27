# frozen_string_literal: true

require_relative "llm_instrumentation"
require_relative "llm_response_wrapper"

class Llm
  prepend LlmInstrumentation

  # Gemini is the only supported provider.
  DEFAULT_MODELS = {
    gemini: "gemini-2.5-flash",
  }.freeze

  # Provider aliases for convenience
  PROVIDER_ALIASES = {
    google: :gemini,
  }.freeze

  attr_reader :provider, :model, :client

  def initialize(provider: :gemini, model: nil)
    @provider = normalize_provider(provider)
    @model = model || DEFAULT_MODELS[@provider] || DEFAULT_MODELS[:gemini]
    @client = create_client
  end

  def chat(messages:, schema: nil, &block)
    chat_client = RubyLLM.chat(model: @model, provider: @provider)
    chat_client.with_schema(schema) if schema

    prompt = apply_messages(chat_client, messages)

    if block_given?
      chat_client.ask(prompt, &block)
    else
      response = chat_client.ask(prompt)
      LlmResponseWrapper.new(response)
    end
  rescue StandardError => e
    Rails.logger.error("LLM Error [#{@provider}/#{@model}]: #{e.message}")
    raise
  end

  def self.provider_configured?(provider)
    provider_sym = provider.to_s.downcase.to_sym
    normalized = PROVIDER_ALIASES[provider_sym] || provider_sym

    case normalized
    when :gemini
      RubyLLM.config.gemini_api_key.present?
    else
      false
    end
  rescue StandardError
    false
  end

  def self.available_providers
    [:gemini].select { |p| provider_configured?(p) }
  end

  private

  # RubyLLM requires a message's content to be a String, so a
  # [{ role:, content: }, ...] array cannot be handed to #ask directly.
  # System turns become chat instructions; the remaining turns are joined
  # into the single user prompt that #ask expects.
  def apply_messages(chat_client, messages)
    return messages unless messages.is_a?(Array)

    instructions = []
    user_turns = []

    messages.each do |message|
      next unless message.is_a?(Hash)

      role = (message[:role] || message["role"]).to_s
      content = (message[:content] || message["content"]).to_s
      next if content.blank?

      if role == "system"
        instructions << content
      else
        user_turns << content
      end
    end

    chat_client.with_instructions(instructions.join("\n\n")) if instructions.any?

    user_turns.join("\n\n")
  end

  def normalize_provider(provider)
    provider_sym = provider.to_s.downcase.to_sym
    PROVIDER_ALIASES[provider_sym] || provider_sym
  end

  def create_client
    unless self.class.provider_configured?(@provider)
      available = self.class.available_providers
      if available.empty?
        raise StandardError, "No LLM providers configured. Please set API keys in config/initializers/ruby_llm.rb"
      else
        Rails.logger.warn("Provider #{@provider} not configured, available: #{available.join(", ")}")
      end
    end

    :ruby_llm
  end
end
