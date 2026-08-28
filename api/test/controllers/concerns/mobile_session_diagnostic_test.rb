# frozen_string_literal: true

require "test_helper"

class MobileSessionDiagnosticTest < ActiveSupport::TestCase
  test "returns no metadata when the session cookie is absent" do
    assert_empty ApplicationController.mobile_session_cookie_metadata("other=value")
  end

  test "reports only length and a truncated fingerprint" do
    value = "sensitive-session-cookie"

    metadata = ApplicationController.mobile_session_cookie_metadata(
      "other=value; _campsite_api_session=#{value}; another=value",
    )

    assert_equal(
      [{ length: value.bytesize, fingerprint: Digest::SHA256.hexdigest(value)[0, 16] }],
      metadata,
    )
    assert_not_includes metadata.to_json, value
  end

  test "preserves duplicate session cookies as separate metadata entries" do
    metadata = ApplicationController.mobile_session_cookie_metadata(
      "_campsite_api_session=first; _campsite_api_session=second",
    )

    assert_equal 2, metadata.length
    assert_equal [5, 6], metadata.pluck(:length)
    assert_equal 2, metadata.pluck(:fingerprint).uniq.length
  end
end
