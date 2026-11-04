# frozen_string_literal: true

class LlmResponseWrapper
  TokenUsage = Struct.new(:prompt_tokens, :completion_tokens, :total_tokens, :cached_tokens, keyword_init: true)

  attr_reader :content

  def initialize(response)
    @response = response
    @content = response.content

    # Extract token counts from response
    @input_tokens = extract_input_tokens(response)
    @output_tokens = extract_output_tokens(response)
    @cached_tokens = extract_cached_tokens(response)
  end

  def to_s
    @content
  end

  def to_str
    @content
  end

  # RubyLLM 2.0 returns structured-output responses as a JSON string in
  # #content and exposes the decoded Hash via #parsed. Older responses (and
  # test doubles) hand back the Hash directly, so accept both.
  def parsed
    return @content if @content.is_a?(Hash)
    return @response.parsed if @response.respond_to?(:parsed)

    nil
  rescue JSON::ParserError
    nil
  end

  def usage
    return unless @input_tokens || @output_tokens

    TokenUsage.new(
      prompt_tokens: @input_tokens,
      completion_tokens: @output_tokens,
      total_tokens: (@input_tokens.to_i + @output_tokens.to_i),
      cached_tokens: @cached_tokens,
    )
  end

  def usage_metadata
    usage
  end

  private

  def extract_input_tokens(response)
    return response.input_tokens if response.respond_to?(:input_tokens) && response.input_tokens

    tokens = response_tokens(response)
    return tokens.input if tokens&.input

    if response.respond_to?(:raw) && response.raw.is_a?(Hash)
      metadata = response.raw["usageMetadata"] || response.raw[:usageMetadata]
      return metadata["promptTokenCount"] || metadata[:promptTokenCount] if metadata
    end

    nil
  end

  def extract_output_tokens(response)
    return response.output_tokens if response.respond_to?(:output_tokens) && response.output_tokens

    tokens = response_tokens(response)
    return tokens.output if tokens&.output

    if response.respond_to?(:raw) && response.raw.is_a?(Hash)
      metadata = response.raw["usageMetadata"] || response.raw[:usageMetadata]
      return metadata["candidatesTokenCount"] || metadata[:candidatesTokenCount] if metadata
    end

    nil
  end

  # RubyLLM 2.0 moved per-message token counts off the message and onto a
  # RubyLLM::Tokens value object at Message#tokens.
  def extract_cached_tokens(response)
    return response.cached_tokens if response.respond_to?(:cached_tokens) && response.cached_tokens

    tokens = response_tokens(response)
    tokens.cache_read if tokens.respond_to?(:cache_read)
  end

  def response_tokens(response)
    return unless response.respond_to?(:tokens)

    tokens = response.tokens
    tokens if tokens.respond_to?(:input) && tokens.respond_to?(:output)
  end
end
