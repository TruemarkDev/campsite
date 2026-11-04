# frozen_string_literal: true

module Tts
  class ElevenLabsProvider
    class Error < Tts::Error; end

    DEFAULT_MODEL = "eleven_multilingual_v2"

    def initialize(api_key: Rails.application.credentials.dig(:elevenlabs, :api_key))
      @api_key = api_key
    end

    def call(text:, voice_id: nil)
      raise Error, "ElevenLabs API key is not configured." if @api_key.blank?
      raise Error, "An ElevenLabs voice id is required." if voice_id.blank?
      raise Error, "Text is required." if text.blank?

      response = connection.post("v1/text-to-speech/#{CGI.escapeURIComponent(voice_id)}/stream") do |request|
        request.params["output_format"] = "mp3_44100_128"
        request.body = { text: text, model_id: DEFAULT_MODEL }.to_json
      end
      raise Error, "ElevenLabs returned HTTP #{response.status}." unless response.success?
      raise Error, "ElevenLabs returned no audio." if response.body.blank?

      { bytes: response.body, content_type: response.headers["content-type"].presence || "audio/mpeg" }
    rescue Faraday::Error => e
      raise Error, "ElevenLabs request failed: #{e.class}"
    end

    private

    def connection
      @connection ||= Faraday.new(
        url: "https://api.elevenlabs.io/",
        headers: { "Content-Type" => "application/json", "xi-api-key" => @api_key },
      )
    end
  end
end
