# frozen_string_literal: true

module LlmObservability
  extend ActiveSupport::Concern

  def add_llm_context(operation_type:, subject_type: nil, subject_id: nil, comment_id: nil, call_id: nil)
    Thread.current[:llm_context] = {
      operation_type: operation_type,
      subject_type: subject_type,
      subject_id: subject_id,
      comment_id: comment_id,
      call_id: call_id,
    }.compact
  end

  def track_cache_hit(is_cache_hit)
    span = OpenTelemetry::Trace.current_span
    return unless span.recording?

    span.set_attribute("llm.cache_hit", is_cache_hit)
  end

  def clear_llm_context
    Thread.current[:llm_context] = nil
  end
end
