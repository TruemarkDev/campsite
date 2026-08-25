# frozen_string_literal: true

require "tmpdir"

class TranscribeAttachmentJob < BaseJob
  sidekiq_options queue: "background", retry: 3

  def perform(attachment_id)
    attachment = Attachment.find(attachment_id)
    source = Down.download(attachment.url)

    Dir.mktmpdir("attachment-audio") do |directory|
      wav_path = File.join(directory, "audio.wav")
      FFMPEG::Movie.new(source.path).transcode(
        wav_path,
        audio_codec: "pcm_s16le",
        audio_sample_rate: 16_000,
        audio_channels: 1,
      )
      vtt = Stt::WhisperCppClient.new.call(wav_path)

      attachment.update!(transcription_vtt: vtt, transcription_job_status: "succeeded")
    end
  rescue StandardError
    attachment&.update_column(:transcription_job_status, "failed")
    raise
  ensure
    source&.close!
  end
end
