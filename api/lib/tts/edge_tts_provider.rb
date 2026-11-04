# frozen_string_literal: true

require "open3"

module Tts
  class EdgeTtsProvider
    class Error < Tts::Error; end

    DEFAULT_VOICE = "en-US-AriaNeural"

    def initialize(binary: ENV.fetch("EDGE_TTS_BINARY", "edge-tts"))
      @binary = binary
    end

    def call(text:, voice_id: nil)
      raise Error, "Text is required." if text.blank?

      stdout, stderr, status = Open3.capture3(
        @binary,
        "--text",
        text,
        "--voice",
        voice_id.presence || DEFAULT_VOICE,
        "--write-media",
        "-",
      )
      raise Error, "edge-tts failed: #{stderr.to_s.strip.presence || "unknown error"}" unless status.success?
      raise Error, "edge-tts returned no audio." if stdout.empty?

      { bytes: stdout, content_type: "audio/mpeg" }
    rescue Errno::ENOENT
      raise Error, "edge-tts binary not found: #{@binary}"
    end
  end
end
