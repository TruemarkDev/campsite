# frozen_string_literal: true

require "test_helper"

module Tts
  class ServiceTest < ActiveSupport::TestCase
    test "uses Edge by default" do
      Rails.application.credentials.stubs(:dig).with(:tts, :provider).returns(nil)
      edge = mock
      Tts::EdgeTtsProvider.expects(:new).returns(edge)
      edge.expects(:call).with(text: "Hello", voice_id: nil).returns(bytes: "audio", content_type: "audio/mpeg")

      Tts::Service.call(text: "Hello")
    end

    test "uses ElevenLabs when configured" do
      Rails.application.credentials.stubs(:dig).with(:tts, :provider).returns("elevenlabs")
      eleven_labs = mock
      Tts::ElevenLabsProvider.expects(:new).returns(eleven_labs)
      eleven_labs.expects(:call).with(text: "Hello", voice_id: "voice-1").returns(bytes: "audio", content_type: "audio/mpeg")

      Tts::Service.call(text: "Hello", voice_id: "voice-1")
    end

    test "falls back to Edge when ElevenLabs fails" do
      Rails.application.credentials.stubs(:dig).with(:tts, :provider).returns("elevenlabs")
      eleven_labs = mock
      edge = mock
      Tts::ElevenLabsProvider.expects(:new).returns(eleven_labs)
      eleven_labs.expects(:call).raises(Tts::ElevenLabsProvider::Error, "invalid credentials")
      Tts::EdgeTtsProvider.expects(:new).returns(edge)
      edge.expects(:call).with(text: "Hello", voice_id: "voice-1").returns(bytes: "audio", content_type: "audio/mpeg")

      Tts::Service.call(text: "Hello", voice_id: "voice-1")
    end
  end
end
