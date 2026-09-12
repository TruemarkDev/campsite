# frozen_string_literal: true

require "test_helper"

class ProjectBeadsSnapshotTest < ActiveSupport::TestCase
  setup do
    @admin = create(:organization_membership, :admin)
    @project = create(:project, organization: @admin.organization, creator: @admin)
    @project.add_member!(@admin)
    @application = create(:oauth_application, owner: @admin.organization, creator: @admin)
    @project.add_oauth_application!(@application)
    @source = ProjectBeadsSource.create!(
      project: @project,
      oauth_application: @application,
      source_project_id: "campsite.board",
      repository_display_name: "Campsite",
      verified_at: Time.current,
    )
  end

  test "oauth applications default to non-agent" do
    assert_not @application.agent_capable?
  end

  test "source rejects a detached connector" do
    @project.remove_oauth_application!(@application)

    assert_not @source.valid?
    assert_includes @source.errors[:oauth_application], "must have a kept project attachment"
  end

  test "source rejects another organization duplicate binding and discarded connector" do
    other_application = create(:oauth_application)
    @source.oauth_application = other_application
    assert_not @source.valid?
    assert_includes @source.errors[:oauth_application], "must belong to the project organization"

    duplicate = @source.reload.dup
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:project_id], "has already been taken"

    @application.discard!
    assert_not @source.reload.valid?
  end

  test "roster follows classification and attachment without inferring presence" do
    generic = create(:oauth_application, owner: @admin.organization, creator: @admin)
    @project.add_oauth_application!(generic)
    assert_equal [@application.id], @source.roster_entries.map { |entry| entry[:application].id }
    assert_equal ["Beads publisher"], @source.roster_entries.first[:roles]

    generic.update!(agent_capable: true)
    assert_includes @source.roster_entries.map { |entry| entry[:application].id }, generic.id
    generic.update!(agent_capable: false)
    assert_not_includes @source.roster_entries.map { |entry| entry[:application].id }, generic.id

    snapshot = ProjectBeadsSnapshot.ingest!(source: @source, attributes: snapshot_payload)
    @project.remove_oauth_application!(@application)
    assert_empty @source.roster_entries
    assert_equal snapshot.id, @source.reload.current_snapshot_id
  end

  test "deleting a project removes cached source and snapshots" do
    snapshot = ProjectBeadsSnapshot.ingest!(source: @source, attributes: snapshot_payload)
    @project.destroy!
    assert_not ProjectBeadsSource.exists?(@source.id)
    assert_not ProjectBeadsSnapshot.exists?(snapshot.id)
  end

  test "validates, persists, and idempotently reuses a safe snapshot" do
    payload = snapshot_payload

    assert_difference -> { ProjectBeadsSnapshot.count }, 1 do
      @snapshot = ProjectBeadsSnapshot.ingest!(source: @source, attributes: payload)
    end
    assert_no_difference -> { ProjectBeadsSnapshot.count } do
      assert_equal @snapshot, ProjectBeadsSnapshot.ingest!(source: @source, attributes: payload)
    end
    assert_equal @snapshot, @source.reload.current_snapshot
    assert_equal "Ready", @snapshot.payload.first.fetch("board_state")
  end

  test "rejects unknown or duplicate issue fields without moving the current pointer" do
    payload = snapshot_payload
    first = ProjectBeadsSnapshot.ingest!(source: @source, attributes: payload)
    invalid = snapshot_payload(collected_at: 1.minute.from_now)
    invalid.fetch("issues").first["description"] = "must not cross the disclosure boundary"
    invalid["digest"] = digest(invalid.except("digest"))

    assert_raises(ProjectBeadsSnapshotSchema::Invalid) do
      ProjectBeadsSnapshot.ingest!(source: @source, attributes: invalid)
    end
    assert_equal first, @source.reload.current_snapshot
  end

  test "accepts a deferred issue in the Deferred column" do
    payload = snapshot_payload
    issue = payload.fetch("issues").first
    issue["status"] = "deferred"
    issue["board_state"] = "Deferred"
    payload["digest"] = digest(payload.except("digest"))

    snapshot = ProjectBeadsSnapshot.ingest!(source: @source, attributes: payload)

    assert_equal "Deferred", snapshot.payload.first.fetch("board_state")
  end

  test "rejects non-object snapshots issues and dependencies without persisting" do
    [nil, "invalid", 42, [], true].each do |value|
      assert_no_difference -> { ProjectBeadsSnapshot.count } do
        assert_raises(ProjectBeadsSnapshotSchema::Invalid) do
          ProjectBeadsSnapshot.ingest!(source: @source, attributes: value)
        end

        payload = snapshot_payload
        payload["issues"] = [value]
        assert_raises(ProjectBeadsSnapshotSchema::Invalid) do
          ProjectBeadsSnapshot.ingest!(source: @source, attributes: payload)
        end

        payload = snapshot_payload
        payload["issues"].first["dependencies"] = [value]
        assert_raises(ProjectBeadsSnapshotSchema::Invalid) do
          ProjectBeadsSnapshot.ingest!(source: @source, attributes: payload)
        end
      end
    end
  end

  test "retains an older accepted snapshot for audit without replacing the current snapshot" do
    current = ProjectBeadsSnapshot.ingest!(source: @source, attributes: snapshot_payload)
    older_payload = snapshot_payload(collected_at: 1.hour.ago, revision: "older")
    older = ProjectBeadsSnapshot.ingest!(source: @source, attributes: older_payload)

    assert_not_equal current, older
    assert_equal current, @source.reload.current_snapshot
  end

  test "invalidation reaches only attached members and only when the pointer advances" do
    outsider = create(:organization_membership, organization: @admin.organization)
    PusherTriggerJob.clear
    payload = snapshot_payload
    ProjectBeadsSnapshot.ingest!(source: @source, attributes: payload)
    events = PusherTriggerJob.jobs.select { |job| job["args"][1] == "project-beads-board-stale" }
    assert_equal [@admin.user.channel_name], events.map { |job| job["args"][0] }
    assert_not_includes events.map { |job| job["args"][0] }, outsider.user.channel_name

    assert_no_difference -> { PusherTriggerJob.jobs.size } do
      ProjectBeadsSnapshot.ingest!(source: @source, attributes: payload)
      ProjectBeadsSnapshot.ingest!(source: @source, attributes: snapshot_payload(collected_at: 1.hour.ago))
    end
  end

  test "database rejects a current snapshot owned by another source" do
    other_admin = create(:organization_membership, :admin)
    other_project = create(:project, organization: other_admin.organization, creator: other_admin)
    other_project.add_member!(other_admin)
    other_application = create(:oauth_application, owner: other_admin.organization, creator: other_admin)
    other_project.add_oauth_application!(other_application)
    other_source = ProjectBeadsSource.create!(
      project: other_project,
      oauth_application: other_application,
      source_project_id: "other.board",
      repository_display_name: "Other",
      verified_at: Time.current,
    )
    other_snapshot = ProjectBeadsSnapshot.ingest!(source: other_source, attributes: snapshot_payload(source: other_source))

    assert_raises(ActiveRecord::InvalidForeignKey) do
      @source.update_columns(current_snapshot_id: other_snapshot.id)
    end
    assert_nil @source.reload.current_snapshot
  end

  test "destroying a source with a current snapshot removes its snapshots" do
    snapshot = ProjectBeadsSnapshot.ingest!(source: @source, attributes: snapshot_payload)

    assert_difference -> { ProjectBeadsSource.count }, -1 do
      assert_difference -> { ProjectBeadsSnapshot.count }, -1 do
        @source.destroy!
      end
    end
    assert_not ProjectBeadsSnapshot.exists?(snapshot.id)
  end

  test "channel export excludes the attached source snapshot and agent roster" do
    ProjectBeadsSnapshot.ingest!(source: @source, attributes: snapshot_payload)
    @application.update!(agent_capable: true)
    export = create(:data_export, subject: @project, member: @admin)
    resource = create(:data_export_resource, data_export: export, resource_type: :project, resource_id: @project.id)
    resource.expects(:write_to_s3).with do |path, body|
      assert_equal "#{@project.export_root_path}/channel.json", path
      assert_equal %w[accessory archived created_at description id members name private], JSON.parse(body).keys.sort
      assert_not_includes body, @source.source_project_id
      assert_not_includes body, "Read only board"
      assert_not_includes body, @application.public_id
      true
    end

    resource.export_project
  end

  test "invalid snapshot primitives and forbidden fields preserve the last good snapshot" do
    current = ProjectBeadsSnapshot.ingest!(source: @source, attributes: snapshot_payload)
    mutations = [
      ->(payload) { payload["schema_version"] = 2 },
      ->(payload) { payload["source_project_id"] = "other" },
      ->(payload) { payload["issues"] *= 2 },
      ->(payload) { payload["issues"] = Array.new(5_001) { payload["issues"].first } },
      ->(payload) { payload["issues"].first["title"] = "x" * 501 },
      ->(payload) { payload["issues"].first["title"] = "hidden\e[31m" },
      ->(payload) { payload["issues"].first["priority"] = "high" },
      ->(payload) { payload["issues"].first["board_state"] = "Closed" },
      ->(payload) { payload["issues"].first["updated_at"] = "not a timestamp" },
      ->(payload) { payload["issues"].first["notes"] = "private" },
      ->(payload) { payload["issues"].first["dependencies"] = [{ "id" => "other", "type" => "blocks", "description" => "private" }] },
    ]
    mutations.each do |mutate|
      payload = snapshot_payload
      mutate.call(payload)
      payload["digest"] = digest(payload.except("digest"))
      assert_no_difference -> { ProjectBeadsSnapshot.count } do
        assert_raises(ProjectBeadsSnapshotSchema::Invalid) { ProjectBeadsSnapshot.ingest!(source: @source, attributes: payload) }
      end
      assert_equal current, @source.reload.current_snapshot
    end
  end

  test "accepted snapshot metadata cannot be edited" do
    snapshot = ProjectBeadsSnapshot.ingest!(source: @source, attributes: snapshot_payload)
    assert_raises(ActiveRecord::RecordInvalid) { snapshot.update!(revision: "edited") }
    assert_equal "abc123", snapshot.reload.revision
  end

  private

  def snapshot_payload(source: @source, collected_at: Time.current, revision: "abc123")
    payload = {
      "schema_version" => 1,
      "source_id" => source.public_id,
      "source_project_id" => source.source_project_id,
      "beads_version" => "1.2.2",
      "beads_schema_version" => "1",
      "branch" => "main",
      "revision" => revision,
      "collected_at" => collected_at.utc.iso8601(3),
      "issues" => [
        {
          "id" => "campsite-4cl.1",
          "title" => "Read only board",
          "status" => "open",
          "board_state" => "Ready",
          "priority" => 1,
          "issue_type" => "feature",
          "assignee" => nil,
          "owner" => nil,
          "labels" => ["api"],
          "parent_id" => "campsite-4cl",
          "dependencies" => [],
          "created_at" => "2026-08-28T00:00:00.000Z",
          "updated_at" => "2026-08-28T01:00:00.000Z",
          "closed_at" => nil,
        },
      ],
    }
    payload["digest"] = digest(payload)
    payload
  end

  def digest(payload)
    Digest::SHA256.hexdigest(ProjectBeadsSnapshotSchema.canonical_json(payload))
  end
end
