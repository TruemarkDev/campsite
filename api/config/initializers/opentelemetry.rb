# frozen_string_literal: true

require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require "opentelemetry/instrumentation/all"

ENV["OTEL_EXPORTER_OTLP_ENDPOINT"] ||= ENV.fetch("SIGNOZ_ENDPOINT", "http://localhost:4318")

ENV["OTEL_SERVICE_NAME"] ||= "campsite-api"
ENV["OTEL_SERVICE_VERSION"] ||= ENV["RELEASE_SHA"] || "development"
ENV["OTEL_RESOURCE_ATTRIBUTES"] ||= "deployment.environment=#{Rails.env},service.namespace=campsite"

sample_ratio = case Rails.env
when "production" then ENV.fetch("OTEL_TRACE_SAMPLE_RATIO", "0.2")
when "test" then "0.0"
else "1.0"
end
ENV["OTEL_TRACES_SAMPLER"] ||= "parentbased_traceidratio"
ENV["OTEL_TRACES_SAMPLER_ARG"] ||= sample_ratio

OpenTelemetry::SDK.configure do |c|
  c.use_all
end

Rails.logger.info("OpenTelemetry initialized for #{Rails.env} environment")
