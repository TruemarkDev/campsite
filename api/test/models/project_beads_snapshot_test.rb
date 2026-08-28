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

  test "retains an older accepted snapshot for audit without replacing the current snapshot" do
    current = ProjectBeadsSnapshot.ingest!(source: @source, attributes: snapshot_payload)
    older_payload = snapshot_payload(collected_at: 1.hour.ago, revision: "older")
    older = ProjectBeadsSnapshot.ingest!(source: @source, attributes: older_payload)

    assert_not_equal current, older
    assert_equal current, @source.reload.current_snapshot
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
