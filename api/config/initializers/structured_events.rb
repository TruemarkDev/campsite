# frozen_string_literal: true

require "structured_event_subscribers/open_telemetry"

Rails.event.subscribe(StructuredEventSubscribers::OpenTelemetry.new) do |event|
  event[:name].start_with?("campsite.")
end
