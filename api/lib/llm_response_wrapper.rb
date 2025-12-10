# frozen_string_literal: true

class LlmResponseWrapper
  TokenUsage = Struct.new(:prompt_tokens, :completion_tokens, :total_tokens, :cached_tokens, keyword_init: true)

  def initialize(response)
    @response = response
    @content = response.content

    # Extract token counts from response
    @input_tokens = extract_input_tokens(response)
    @output_tokens = extract_output_tokens(response)
    @cached_tokens = response.cached_tokens if response.respond_to?(:cached_tokens)
  end

  def to_s
    @content
  end

  def to_str
    @content
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

    if response.respond_to?(:raw) && response.raw.is_a?(Hash)
      metadata = response.raw["usageMetadata"] || response.raw[:usageMetadata]
      return metadata["promptTokenCount"] || metadata[:promptTokenCount] if metadata
    end

    nil
  end

  def extract_output_tokens(response)
    return response.output_tokens if response.respond_to?(:output_tokens) && response.output_tokens

    if response.respond_to?(:raw) && response.raw.is_a?(Hash)
      metadata = response.raw["usageMetadata"] || response.raw[:usageMetadata]
      return metadata["candidatesTokenCount"] || metadata[:candidatesTokenCount] if metadata
    end

    nil
  end
end
