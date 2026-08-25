# frozen_string_literal: true

module Tts
  class Service
    def self.call(...)
      new.call(...)
    end

    def call(text:, voice_id: nil)
      provider.call(text: text, voice_id: voice_id)
    rescue ElevenLabsProvider::Error => e
      Rails.logger.warn("ElevenLabs TTS unavailable; falling back to edge-tts: #{e.class}")
      EdgeTtsProvider.new.call(text: text, voice_id: voice_id)
    end

    private

    def provider
      @provider ||=
        case Rails.application.credentials.dig(:tts, :provider).presence || "edge"
        when "edge" then EdgeTtsProvider.new
        when "elevenlabs" then ElevenLabsProvider.new
        else raise Error, "Unsupported TTS provider."
        end
    end
  end
end
