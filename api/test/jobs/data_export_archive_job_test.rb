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
      @body = body.respond_to?(:read) ? body.read : body
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

  test "delivered channel archive excludes the Beads source cards and roster" do
    admin = create(:organization_membership, :admin)
    project = create(:project, organization: admin.organization, creator: admin)
    project.add_member!(admin)
    application = create(:oauth_application, owner: admin.organization, creator: admin, agent_capable: true)
    project.add_oauth_application!(application)
    source = ProjectBeadsSource.create!(project: project, oauth_application: application, source_project_id: "private-beads-workspace", repository_display_name: "Private Beads repository", verified_at: Time.current)
    payload = {
      schema_version: 1, source_id: source.public_id, source_project_id: source.source_project_id,
      beads_version: "1.2.2", branch: "main", revision: "private-beads-revision", collected_at: Time.current.iso8601(3),
      issues: [{ id: "beads-private.1", title: "BEADS_CARD_NOT_EXPORTED", status: "open", board_state: "Ready", priority: 1, issue_type: "task", labels: [], dependencies: [], created_at: Time.current.iso8601, updated_at: Time.current.iso8601 }],
    }.deep_stringify_keys
    payload["digest"] = Digest::SHA256.hexdigest(ProjectBeadsSnapshotSchema.canonical_json(payload))
    ProjectBeadsSnapshot.ingest!(source: source, attributes: payload)
    export = create(:data_export, subject: project, member: admin)
    bucket = FakeBucket.new
    DataExport.any_instance.stubs(:export_bucket).returns(bucket)
    OrganizationMailer.expects(:data_export_completed).once.returns(stub(deliver_later: true))

    export.perform
    export.resources.each(&:perform)
    DataExportArchiveJob.new.perform(export.id)

    assert_predicate export.reload, :completed?
    Tempfile.create(["beads-channel-export", ".zip"]) do |file|
      file.binmode
      file.write(bucket.object(export.expected_zip_path).body)
      file.flush
      entries, error, status = Open3.capture3("/usr/bin/unzip", "-Z1", file.path)
      assert_predicate status, :success?, error
      assert_equal ["#{project.export_root_path}/channel.json"], entries.lines.map(&:chomp).reject { |entry| entry.end_with?("/") }
      contents, error, status = Open3.capture3("/usr/bin/unzip", "-p", file.path, "#{project.export_root_path}/channel.json")
      assert_predicate status, :success?, error
      assert_equal %w[accessory archived created_at description id members name private], JSON.parse(contents).keys.sort
      [source.public_id, source.source_project_id, "BEADS_CARD_NOT_EXPORTED", application.public_id, "private-beads-revision"].each do |private_value|
        assert_not_includes contents, private_value
      end
    end
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
