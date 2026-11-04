# frozen_string_literal: true

require "test_helper"
require "open3"
require "tempfile"

class DataExportArchiveJobTest < ActiveSupport::TestCase
  class FakeObject
    attr_reader :key, :body

    def initialize(bucket, key, body = nil)
      @bucket = bucket
      @key = key
      @body = body
    end

    def get(response_target:)
      File.binwrite(response_target, body)
    end

    def put(body:, **)
      @body = body.read
      self
    end

    def delete
      @bucket.delete(key)
    end
  end

  class FakeBucket
    delegate :delete, to: :@objects

    def initialize(objects = {})
      @objects = objects.to_h { |key, body| [key, FakeObject.new(self, key, body)] }
    end

    def object(key)
      @objects[key] ||= FakeObject.new(self, key)
    end

    def objects(prefix:)
      @objects.values.select { |object| object.key.start_with?(prefix) }
    end
  end

  test "archives fragments, completes once, and removes intermediate objects" do
    export = create(:data_export, status: :archiving)
    bucket = FakeBucket.new(
      "#{export.export_prefix}users.json" => "[]",
      "#{export.export_prefix}channels/general/channel.json" => "{}",
    )
    DataExport.any_instance.stubs(:export_bucket).returns(bucket)
    OrganizationMailer.expects(:data_export_completed).once.returns(stub(deliver_later: true))

    DataExportArchiveJob.new.perform(export.id)

    export.reload
    archive = bucket.object(export.expected_zip_path)
    assert_predicate export, :completed?
    assert archive.body.start_with?("PK")
    Tempfile.create(["data-export", ".zip"]) do |file|
      file.binmode
      file.write(archive.body)
      file.flush
      entries, error, status = Open3.capture3("/usr/bin/unzip", "-Z1", file.path)

      assert_predicate status, :success?, error
      file_entries = entries.lines.map(&:chomp).reject { |entry| entry.end_with?("/") }
      assert_equal ["channels/general/channel.json", "users.json"], file_entries.sort
    end
    assert_equal [export.expected_zip_path], bucket.objects(prefix: export.export_prefix).map(&:key)
    assert_enqueued_sidekiq_job DataExportCleanupJob, args: [export.id]

    DataExportArchiveJob.new.perform(export.id)

    assert_equal [export.expected_zip_path], bucket.objects(prefix: export.export_prefix).map(&:key)
  end

  test "does nothing for a failed export" do
    export = create(:data_export, status: :error)
    DataExport.any_instance.expects(:export_bucket).never

    DataExportArchiveJob.new.perform(export.id)
  end

  test "retries an interrupted upload without losing fragments or completing early" do
    export = create(:data_export, status: :archiving)
    fragment = "#{export.export_prefix}users.json"
    bucket = FakeBucket.new(fragment => "[]")
    DataExport.any_instance.stubs(:export_bucket).returns(bucket)
    archive = bucket.object(export.expected_zip_path)
    archive.stubs(:put).raises(IOError, "upload interrupted")
    OrganizationMailer.expects(:data_export_completed).once.returns(stub(deliver_later: true))

    assert_raises(IOError) { DataExportArchiveJob.new.perform(export.id) }

    assert_predicate export.reload, :archiving?
    assert_nil export.completed_at
    assert_equal "[]", bucket.object(fragment).body
    archive.unstub(:put)

    DataExportArchiveJob.new.perform(export.id)
    DataExportArchiveJob.new.perform(export.id)

    assert_predicate export.reload, :completed?
    assert archive.body.start_with?("PK")
    assert_equal [export.expected_zip_path], bucket.objects(prefix: export.export_prefix).map(&:key)
  end

  test "retries a database failure after upload and sends completion only once" do
    export = create(:data_export, status: :archiving)
    fragment = "#{export.export_prefix}users.json"
    bucket = FakeBucket.new(fragment => "[]")
    DataExport.any_instance.stubs(:export_bucket).returns(bucket)
    DataExport.any_instance.stubs(:complete).raises(ActiveRecord::Deadlocked)
    OrganizationMailer.expects(:data_export_completed).once.returns(stub(deliver_later: true))

    assert_raises(ActiveRecord::Deadlocked) { DataExportArchiveJob.new.perform(export.id) }

    assert_predicate export.reload, :archiving?
    assert bucket.object(export.expected_zip_path).body.start_with?("PK")
    assert_equal "[]", bucket.object(fragment).body
    DataExport.any_instance.unstub(:complete)

    DataExportArchiveJob.new.perform(export.id)
    DataExportArchiveJob.new.perform(export.id)

    assert_predicate export.reload, :completed?
    assert_equal [export.expected_zip_path], bucket.objects(prefix: export.export_prefix).map(&:key)
  end

  test "exhausted retries fail an unfinished export but cannot overwrite a completed export" do
    export = create(:data_export, status: :archiving)
    exhausted = DataExportArchiveJob.sidekiq_retries_exhausted_block

    exhausted.call({ "args" => [export.id] })
    assert_predicate export.reload, :error?

    completed = create(:data_export, status: :completed)
    exhausted.call({ "args" => [completed.id] })
    assert_predicate completed.reload, :completed?
  end

  test "rejects an object key that escapes the temporary archive root" do
    export = create(:data_export, status: :archiving)
    bucket = FakeBucket.new("#{export.export_prefix}../escape.json" => "{}")
    DataExport.any_instance.stubs(:export_bucket).returns(bucket)

    assert_raises(DataExportArchiveJob::InvalidObjectPath) do
      DataExportArchiveJob.new.perform(export.id)
    end

    assert_predicate export.reload, :archiving?
  end

  test "fails when an export has no fragments" do
    export = create(:data_export, status: :archiving)
    DataExport.any_instance.stubs(:export_bucket).returns(FakeBucket.new)

    assert_raises(DataExportArchiveJob::ArchiveFailed) do
      DataExportArchiveJob.new.perform(export.id)
    end

    assert_predicate export.reload, :archiving?
  end
end
