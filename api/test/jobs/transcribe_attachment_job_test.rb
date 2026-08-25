# frozen_string_literal: true

require "test_helper"

class TranscribeAttachmentJobTest < ActiveSupport::TestCase
  setup do
    TranscribeAttachmentJob.stubs(:perform_async).returns("job-123")
    @attachment = create(:attachment, file_type: "audio/webm", file_path: "/path/voice.webm")
    @source = stub(path: "/tmp/source.webm", close!: nil)
    Down.stubs(:download).returns(@source)
  end

  test "converts, transcribes, and stores VTT" do
    movie = mock
    movie.expects(:transcode).with(
      regexp_matches(/audio\.wav\z/),
      audio_codec: "pcm_s16le",
      audio_sample_rate: 16_000,
      audio_channels: 1,
    )
    FFMPEG::Movie.stubs(:new).with(@source.path).returns(movie)
    Stt::WhisperCppClient.any_instance.stubs(:call).returns("WEBVTT\n\nHello voice")

    TranscribeAttachmentJob.new.perform(@attachment.id)

    assert_equal "succeeded", @attachment.reload.transcription_job_status
    assert_equal "Hello voice", @attachment.transcript
  end

  test "marks failure and re-raises for Sidekiq retry" do
    FFMPEG::Movie.stubs(:new).raises(FFMPEG::Error, "bad audio")

    assert_raises FFMPEG::Error do
      TranscribeAttachmentJob.new.perform(@attachment.id)
    end
    assert_equal "failed", @attachment.reload.transcription_job_status
  end
end
