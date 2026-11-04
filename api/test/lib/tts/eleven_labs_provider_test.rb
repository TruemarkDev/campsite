# frozen_string_literal: true

require "test_helper"

module Tts
  class ElevenLabsProviderTest < ActiveSupport::TestCase
    test "streams MP3 audio from ElevenLabs" do
      response = stub(success?: true, body: "mp3-bytes".b, headers: { "content-type" => "audio/mpeg" })
      request = stub(params: {})
      request.expects(:body=).with({ text: "Hello", model_id: "eleven_multilingual_v2" }.to_json)
      connection = mock
      connection.expects(:post).with("v1/text-to-speech/voice-1/stream").yields(request).returns(response)
      provider = Tts::ElevenLabsProvider.new(api_key: "secret")
      provider.stubs(:connection).returns(connection)

      result = provider.call(text: "Hello", voice_id: "voice-1")

      assert_equal "mp3-bytes".b, result[:bytes]
      assert_equal "audio/mpeg", result[:content_type]
    end

    test "raises a typed error when credentials are absent" do
      assert_raises(Tts::ElevenLabsProvider::Error) do
        Tts::ElevenLabsProvider.new(api_key: nil).call(text: "Hello", voice_id: "voice-1")
      end
    end
  end
end
