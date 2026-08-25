# frozen_string_literal: true

require "open3"
require "tmpdir"

module Stt
  class WhisperCppClient
    class Error < StandardError; end
    class MissingBinaryError < Error; end
    class MissingModelError < Error; end

    def initialize(
      binary: ENV.fetch("WHISPER_CPP_BINARY", "whisper-cli"),
      model: ENV.fetch("WHISPER_CPP_MODEL", "/opt/whisper.cpp/models/ggml-base.en.bin")
    )
      @binary = binary
      @model = model
    end

    def call(wav_path)
      raise MissingModelError, "whisper.cpp model not found: #{@model}" unless File.file?(@model)

      Dir.mktmpdir("attachment-transcription") do |directory|
        output_prefix = File.join(directory, "transcript")
        _stdout, stderr, status = Open3.capture3(
          @binary,
          "--model",
          @model,
          "--file",
          wav_path.to_s,
          "--output-vtt",
          "--output-file",
          output_prefix,
          "--no-prints",
        )
        raise Error, "whisper.cpp failed: #{stderr.to_s.strip.first(500)}" unless status.success?

        File.read("#{output_prefix}.vtt")
      end
    rescue Errno::ENOENT
      raise MissingBinaryError, "whisper.cpp binary not found: #{@binary}"
    end
  end
end
