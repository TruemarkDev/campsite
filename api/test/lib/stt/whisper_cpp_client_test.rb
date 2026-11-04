# frozen_string_literal: true

require "test_helper"

module Stt
  class WhisperCppClientTest < ActiveSupport::TestCase
    test "runs whisper-cli with an explicit model and returns VTT" do
      status = stub(success?: true)
      File.stubs(:file?).with("/models/base.bin").returns(true)
      File.stubs(:read).with(regexp_matches(/transcript\.vtt\z/)).returns("WEBVTT\n\nHello")
      Open3.expects(:capture3).with(
        "/usr/local/bin/whisper-cli",
        "--model",
        "/models/base.bin",
        "--file",
        "/tmp/audio.wav",
        "--output-vtt",
        "--output-file",
        regexp_matches(/transcript\z/),
        "--no-prints",
      ).returns(["", "", status])

      result = Stt::WhisperCppClient.new(binary: "/usr/local/bin/whisper-cli", model: "/models/base.bin").call("/tmp/audio.wav")

      assert_equal "WEBVTT\n\nHello", result
    end

    test "raises a typed error when the model is absent" do
      File.stubs(:file?).returns(false)

      assert_raises Stt::WhisperCppClient::MissingModelError do
        Stt::WhisperCppClient.new(model: "/missing.bin").call("/tmp/audio.wav")
      end
    end

    test "raises a typed error when the binary is absent" do
      File.stubs(:file?).returns(true)
      Open3.stubs(:capture3).raises(Errno::ENOENT)

      assert_raises Stt::WhisperCppClient::MissingBinaryError do
        Stt::WhisperCppClient.new(binary: "missing-whisper", model: "/models/base.bin").call("/tmp/audio.wav")
      end
    end
  end
end
