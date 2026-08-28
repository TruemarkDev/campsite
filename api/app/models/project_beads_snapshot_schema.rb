# frozen_string_literal: true

require "digest"
require "json"
require "time"

class ProjectBeadsSnapshotSchema
  class Invalid < StandardError; end

  TOP_LEVEL_FIELDS = %w[schema_version source_id source_project_id beads_version beads_schema_version branch revision collected_at digest issues].freeze
  ISSUE_FIELDS = %w[id title status board_state priority issue_type assignee owner labels parent_id dependencies created_at updated_at closed_at].freeze
  DEPENDENCY_FIELDS = %w[id type].freeze
  BOARD_STATES = ["Ready", "In progress", "Blocked", "Deferred", "Closed"].freeze
  STATUSES = %w[open in_progress deferred closed].freeze
  MAX_ISSUES = 5_000
  MAX_LABELS = 50
  MAX_DEPENDENCIES = 100
  MAX_TEXT = 500
  ID_PATTERN = /\A[[:alnum:]][[:alnum:]._-]{0,254}\z/
  CONTROL_PATTERN = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/

  class << self
    def validate!(raw, source:)
      payload = raw.to_h.deep_stringify_keys
      exact_fields!(payload, TOP_LEVEL_FIELDS, "snapshot")
      required!(payload, %w[schema_version source_id source_project_id beads_version branch revision collected_at digest issues])
      invalid!("unsupported schema version") unless payload["schema_version"] == 1
      invalid!("source id mismatch") unless payload["source_id"] == source.public_id
      invalid!("source project id mismatch") unless payload["source_project_id"] == source.source_project_id
      digest_input = payload.except("digest").deep_dup

      %w[beads_version beads_schema_version branch revision].each { |field| bounded_text!(payload[field], field, nullable: field == "beads_schema_version") }
      payload["collected_at"] = parse_time!(payload["collected_at"], "collected_at")
      issues = payload["issues"]
      invalid!("issues must be an array") unless issues.is_a?(Array)
      invalid!("too many issues") if issues.length > MAX_ISSUES
      payload["issues"] = issues.map.with_index { |issue, index| validate_issue!(issue, index) }
      invalid!("duplicate issue id") unless payload["issues"].map { |issue| issue.fetch("id") }.uniq.length == payload["issues"].length

      expected = Digest::SHA256.hexdigest(canonical_json(digest_input))
      invalid!("digest mismatch") unless secure_compare(expected, payload["digest"])
      payload
    rescue ArgumentError, TypeError => error
      raise Invalid, error.message
    end

    def canonical_json(value)
      case value
      when Hash
        "{" + value.keys.sort.map { |key| "#{JSON.generate(key)}:#{canonical_json(value.fetch(key))}" }.join(",") + "}"
      when Array
        "[" + value.map { |item| canonical_json(item) }.join(",") + "]"
      when Time, ActiveSupport::TimeWithZone
        JSON.generate(value.iso8601(3))
      else
        JSON.generate(value)
      end
    end

    private

    def validate_issue!(raw, index)
      issue = raw.to_h.deep_stringify_keys
      exact_fields!(issue, ISSUE_FIELDS, "issue #{index}")
      required!(issue, %w[id title status board_state priority issue_type labels dependencies created_at updated_at])
      identifier!(issue["id"], "issue id")
      bounded_text!(issue["title"], "title")
      invalid!("invalid status") unless STATUSES.include?(issue["status"])
      invalid!("invalid board state") unless BOARD_STATES.include?(issue["board_state"])
      validate_state!(issue)
      invalid!("priority must be an integer") unless issue["priority"].is_a?(Integer)
      bounded_text!(issue["issue_type"], "issue_type")
      %w[assignee owner].each { |field| bounded_text!(issue[field], field, nullable: true) }
      identifier!(issue["parent_id"], "parent_id", nullable: true)
      validate_string_array!(issue["labels"], "labels", MAX_LABELS)
      validate_dependencies!(issue["dependencies"])
      %w[created_at updated_at closed_at].each { |field| issue[field] = parse_time!(issue[field], field, nullable: field == "closed_at") }
      issue
    end

    def validate_state!(issue)
      expected = if issue["status"] == "closed"
        "Closed"
      elsif issue["status"] == "deferred"
        "Deferred"
      elsif issue["board_state"] == "Blocked"
        "Blocked"
      elsif issue["status"] == "in_progress"
        "In progress"
      else
        "Ready"
      end
      invalid!("incoherent board state") unless issue["board_state"] == expected
    end

    def validate_dependencies!(dependencies)
      invalid!("dependencies must be an array") unless dependencies.is_a?(Array)
      invalid!("too many dependencies") if dependencies.length > MAX_DEPENDENCIES
      dependencies.each do |dependency|
        dependency = dependency.to_h.deep_stringify_keys
        exact_fields!(dependency, DEPENDENCY_FIELDS, "dependency")
        required!(dependency, DEPENDENCY_FIELDS)
        identifier!(dependency["id"], "dependency id")
        bounded_text!(dependency["type"], "dependency type")
      end
    end

    def validate_string_array!(values, field, maximum)
      invalid!("#{field} must be an array") unless values.is_a?(Array)
      invalid!("too many #{field}") if values.length > maximum
      values.each { |value| bounded_text!(value, field) }
    end

    def exact_fields!(value, allowed, label)
      invalid!("#{label} must be an object") unless value.is_a?(Hash)
      unknown = value.keys - allowed
      invalid!("unknown #{label} fields: #{unknown.join(", ")}") if unknown.any?
    end

    def required!(value, fields)
      missing = fields.reject { |field| value.key?(field) }
      invalid!("missing fields: #{missing.join(", ")}") if missing.any?
    end

    def identifier!(value, field, nullable: false)
      return if nullable && value.nil?
      invalid!("invalid #{field}") unless value.is_a?(String) && value.match?(ID_PATTERN)
    end

    def bounded_text!(value, field, nullable: false)
      return if nullable && value.nil?
      invalid!("invalid #{field}") unless value.is_a?(String) && value.bytesize <= MAX_TEXT && !value.match?(CONTROL_PATTERN)
    end

    def parse_time!(value, field, nullable: false)
      return if nullable && value.nil?
      invalid!("invalid #{field}") unless value.is_a?(String)
      Time.iso8601(value)
    rescue ArgumentError
      invalid!("invalid #{field}")
    end

    def secure_compare(expected, actual)
      actual.is_a?(String) && actual.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(expected, actual)
    end

    def invalid!(message)
      raise Invalid, message
    end
  end
end
