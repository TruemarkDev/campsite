# frozen_string_literal: true

require "test_helper"

class ReferenceableTest < ActiveSupport::TestCase
  class TestReferenceable
    include Referenceable
  end

  setup do
    @referenceable = TestReferenceable.new
    @app_url = Campsite.base_app_url.to_s
    @alternate_scheme_url = @app_url.sub(/\Ahttps?/, @app_url.start_with?("https:") ? "http" : "https")
  end

  test "recognizes current-scheme post and note URLs" do
    assert_equal ["post123"], @referenceable.extract_post_ids("#{@app_url}/acme/posts/post123")
    assert_equal ["note456"], @referenceable.extract_note_ids("#{@app_url}/acme/notes/note456")
  end

  test "recognizes historical URLs using the alternate HTTP scheme" do
    assert_equal ["post123"], @referenceable.extract_post_ids("#{@alternate_scheme_url}/acme/posts/post123")
    assert_equal ["note456"], @referenceable.extract_note_ids("#{@alternate_scheme_url}/acme/notes/note456")
  end

  test "does not match a different host" do
    assert_not @referenceable.contains_campsite_urls?("https://not-#{Campsite.base_app_url.host}/acme/posts/post123")
  end
end
