# frozen_string_literal: true

module StructuredEventSubscribers
  class OpenTelemetry
    def initialize(
      logger: Rails.logger,
      parameter_filter: ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters),
      trace: ::OpenTelemetry::Trace
    )
      @logger = logger
      @parameter_filter = parameter_filter
      @trace = trace
    end

    def emit(event)
      attributes = event_attributes(event)
      @logger.info({ event: event.fetch(:name) }.merge(attributes))

      span = @trace.current_span
      span.add_event(event.fetch(:name), attributes: attributes) if span.recording?
    end

    private

    def event_attributes(event)
      attributes = {}
      append_attributes(attributes, event[:payload], prefix: nil)
      append_attributes(attributes, event[:tags], prefix: "tag")
      append_attributes(attributes, event[:context], prefix: "context")
      @parameter_filter.filter(attributes)
    end

    def append_attributes(attributes, values, prefix:)
      return unless values.respond_to?(:each_pair)

      values.each_pair do |key, value|
        value = normalize_attribute(value)
        next if value.nil?

        name = [prefix, key].compact.join(".")
        attributes[name] = value
      end
    end

    def normalize_attribute(value)
      case value
      when String, Numeric, true, false
        value
      when Symbol
        value.to_s
      when Array
        values = value.filter_map { |item| normalize_attribute(item) }
        values if values.all? { |item| item.class == values.first.class }
      end
    end
  end
end
