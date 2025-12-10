# frozen_string_literal: true

module LlmInstrumentation
  def chat(messages:, operation_type: nil, subject_type: nil, subject_id: nil, **options, &block)
    start_time = Time.current
    streaming = block_given?

    context = Thread.current[:llm_context] || {}
    operation_type ||= context[:operation_type]
    subject_type ||= context[:subject_type]
    subject_id ||= context[:subject_id]

    attributes = {
      "llm.provider" => provider.to_s,
      "llm.model" => model.to_s,
      "llm.streaming" => streaming,
      "llm.message_count" => messages.is_a?(Array) ? messages.size : 1,
    }

    attributes["llm.business.operation_type"] = operation_type if operation_type
    attributes["llm.business.subject_type"] = subject_type if subject_type
    attributes["llm.business.subject_id"] = subject_id if subject_id
    attributes["llm.business.comment_id"] = context[:comment_id] if context[:comment_id]
    attributes["llm.business.call_id"] = context[:call_id] if context[:call_id]

    span_options = {
      attributes: attributes,
      kind: :client,
    }

    tracer.in_span("llm.chat", **span_options) do |span|
      result = super(messages: messages, **options, &block)

      # Calculate duration
      duration_ms = ((Time.current - start_time) * 1000).round(2)

      # Set success attributes
      span.set_attribute("llm.status", "success")
      span.set_attribute("llm.duration_ms", duration_ms)

      extract_token_usage(span, result)

      result
    rescue StandardError => e
      duration_ms = ((Time.current - start_time) * 1000).round(2)

      # Set error attributes
      span.set_attribute("llm.status", "error")
      span.set_attribute("llm.duration_ms", duration_ms)
      span.set_attribute("llm.error.type", e.class.name)
      span.set_attribute("llm.error.message", e.message)

      # Record exception
      span.record_exception(e)
      span.status = OpenTelemetry::Trace::Status.error("LLM request failed: #{e.message}")

      raise
    ensure
      Thread.current[:llm_context] = nil if context.present?
    end
  end

  private

  def tracer
    @tracer ||= OpenTelemetry.tracer_provider.tracer("llm", "1.0.0")
  end

  def extract_token_usage(span, result)
    usage = if result.respond_to?(:usage)
      result.usage
    elsif result.respond_to?(:usage_metadata)
      result.usage_metadata
    end

    return unless usage

    # OpenAI format (prompt_tokens, completion_tokens, total_tokens)
    if usage.respond_to?(:prompt_tokens) && usage.respond_to?(:completion_tokens)
      input = usage.prompt_tokens.to_i
      output = usage.completion_tokens.to_i
      total = (usage.total_tokens || (usage.prompt_tokens + usage.completion_tokens)).to_i

      span.set_attribute("llm.token_usage.input", input)
      span.set_attribute("llm.token_usage.output", output)
      span.set_attribute("llm.token_usage.total", total)
      span.set_attribute("llm.token_usage.estimated", false)
    # Anthropic format (input_tokens, output_tokens)
    elsif usage.respond_to?(:input_tokens) && usage.respond_to?(:output_tokens)
      input = usage.input_tokens.to_i
      output = usage.output_tokens.to_i
      total = (usage.input_tokens + usage.output_tokens).to_i

      span.set_attribute("llm.token_usage.input", input)
      span.set_attribute("llm.token_usage.output", output)
      span.set_attribute("llm.token_usage.total", total)
      span.set_attribute("llm.token_usage.estimated", false)
    # Gemini format (promptTokenCount, candidatesTokenCount, totalTokenCount)
    elsif usage.respond_to?(:prompt_token_count) || usage.respond_to?(:promptTokenCount)
      input_tokens = usage.respond_to?(:prompt_token_count) ? usage.prompt_token_count : usage.promptTokenCount
      output_tokens = usage.respond_to?(:candidates_token_count) ? usage.candidates_token_count : usage.candidatesTokenCount
      total_tokens = usage.respond_to?(:total_token_count) ? usage.total_token_count : usage.totalTokenCount

      span.set_attribute("llm.token_usage.input", input_tokens.to_i) if input_tokens
      span.set_attribute("llm.token_usage.output", output_tokens.to_i) if output_tokens
      span.set_attribute("llm.token_usage.total", (total_tokens || (input_tokens.to_i + output_tokens.to_i)).to_i)
      span.set_attribute("llm.token_usage.estimated", false)
    elsif usage.is_a?(Hash)
      input_tokens = usage["promptTokenCount"] || usage[:promptTokenCount] || usage["prompt_token_count"] || usage[:prompt_token_count]
      output_tokens = usage["candidatesTokenCount"] || usage[:candidatesTokenCount] || usage["candidates_token_count"] || usage[:candidates_token_count]
      total_tokens = usage["totalTokenCount"] || usage[:totalTokenCount] || usage["total_token_count"] || usage[:total_token_count]

      if input_tokens && output_tokens
        span.set_attribute("llm.token_usage.input", input_tokens.to_i)
        span.set_attribute("llm.token_usage.output", output_tokens.to_i)
        span.set_attribute("llm.token_usage.total", (total_tokens || (input_tokens + output_tokens)).to_i)
        span.set_attribute("llm.token_usage.estimated", false)
      end
    end
  rescue StandardError => e
    Rails.logger.error("Error extracting token usage: #{e.message}")
  end
end
