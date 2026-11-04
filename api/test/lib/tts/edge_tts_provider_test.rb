# frozen_string_literal: true

require "test_helper"

module Tts
  class EdgeTtsProviderTest < ActiveSupport::TestCase
    test "returns generated MP3 bytes" do
      status = stub(success?: true)
      Open3.expects(:capture3)
        .with("edge-tts", "--text", "Hello", "--voice", "voice-1", "--write-media", "-")
        .returns(["mp3-bytes".b, "", status])

      result = Tts::EdgeTtsProvider.new.call(text: "Hello", voice_id: "voice-1")

      assert_equal "mp3-bytes".b, result[:bytes]
      assert_equal "audio/mpeg", result[:content_type]
    end

    test "raises a typed error when the binary is missing" do
      Open3.stubs(:capture3).raises(Errno::ENOENT)

      error = assert_raises(Tts::EdgeTtsProvider::Error) do
        Tts::EdgeTtsProvider.new.call(text: "Hello")
      end

      assert_match(/binary not found/, error.message)
    end
  end
end
