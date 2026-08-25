# frozen_string_literal: true

require "test_helper"

module StructuredEventSubscribers
  class OpenTelemetryTest < ActiveSupport::TestCase
    test "writes filtered event attributes to logs and the active span" do
      logger = mock
      span = mock
      trace = mock
      filter = ActiveSupport::ParameterFilter.new([:token])
      subscriber = OpenTelemetry.new(logger: logger, parameter_filter: filter, trace: trace)
      attributes = {
        "outcome" => "success",
        "token" => "[FILTERED]",
        "tag.component" => "oauth",
        "context.request_id" => "request-123",
      }

      logger.expects(:info).with({ event: "campsite.oauth.cimd.resolve" }.merge(attributes))
      trace.expects(:current_span).returns(span)
      span.expects(:recording?).returns(true)
      span.expects(:add_event).with("campsite.oauth.cimd.resolve", attributes: attributes)

      subscriber.emit(
        name: "campsite.oauth.cimd.resolve",
        payload: { outcome: :success, token: "secret", ignored: Object.new },
        tags: { component: :oauth },
        context: { request_id: "request-123" },
      )
    end

    test "does not add an event to a non-recording span" do
      logger = stub(info: nil)
      span = stub(recording?: false)
      trace = stub(current_span: span)
      subscriber = OpenTelemetry.new(logger: logger, parameter_filter: ActiveSupport::ParameterFilter.new([]), trace: trace)

      span.expects(:add_event).never
      subscriber.emit(name: "campsite.test", payload: {}, tags: {}, context: {})
    end
  end
end
