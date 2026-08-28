# frozen_string_literal: true

require "test_helper"

class DataExportTest < ActiveSupport::TestCase
  test "queues archive after all resources complete" do
    data_export = create(:data_export)
    create(:data_export_resource, :completed, data_export: data_export)

    data_export.check_completed

    assert_predicate data_export.reload, :archiving?
    assert_enqueued_sidekiq_job DataExportArchiveJob, args: [data_export.id], queue: "exports"
  end

  test "marks export as error when a resource fails" do
    data_export = create(:data_export)
    create(:data_export_resource, status: :error, data_export: data_export)

    data_export.check_completed

    assert_predicate data_export.reload, :error?
    assert_enqueued_sidekiq_job DataExportCleanupJob, args: [data_export.id], in: 2.days
    refute_enqueued_sidekiq_job DataExportArchiveJob, args: [data_export.id]
  end

  test "does not queue archive while resources are pending" do
    data_export = create(:data_export)
    create(:data_export_resource, data_export: data_export)

    data_export.check_completed

    assert_predicate data_export.reload, :pending?
    refute_enqueued_sidekiq_job DataExportArchiveJob, args: [data_export.id]
  end

  test "complete is idempotent" do
    data_export = create(:data_export, status: :archiving)
    OrganizationMailer.expects(:data_export_completed).once.returns(stub(deliver_later: true))

    assert data_export.complete(data_export.expected_zip_path)
    assert_not data_export.complete(data_export.expected_zip_path)

    assert_predicate data_export.reload, :completed?
    assert_equal data_export.expected_zip_path, data_export.zip_path
    assert_enqueued_sidekiq_job DataExportCleanupJob, args: [data_export.id], count: 1
  end

  test "refuses an unexpected archive path" do
    data_export = create(:data_export, status: :archiving)

    assert_raises(DataExport::InvalidZipPath) { data_export.complete("other/export.zip") }
  end

  test "creates resources for accessible projects and posts" do
    org = create(:organization)
    data_export = create(:data_export, subject: org)

    project = create(:project, organization: org)
    post = create(:post, project: project)
    call = create(:call, :recorded, :completed, project: project)
    note = create(:note, project: project)

    private_project = create(:project, organization: org, private: true)
    private_post = create(:post, project: private_project)
    private_call = create(:call, :recorded, :completed, project: private_project)
    private_note = create(:note, project: private_project)

    assert_difference -> { DataExportResource.count }, 6 do
      data_export.create_resources
    end

    assert_not_nil data_export.resources.find_by(resource_type: :users)
    assert_not_nil data_export.resources.find_by(resource_type: :project, resource_id: project.id)
    assert_not_nil data_export.resources.find_by(resource_type: :post, resource_id: post.id)
    assert_not_nil data_export.resources.find_by(resource_type: :call, resource_id: call.id)
    assert_not_nil data_export.resources.find_by(resource_type: :note, resource_id: note.id)
    assert_not_nil data_export.resources.find_by(resource_type: :call_recording, resource_id: call.recordings.first.id)

    assert_nil data_export.resources.find_by(resource_type: :project, resource_id: private_project.id)
    assert_nil data_export.resources.find_by(resource_type: :post, resource_id: private_post.id)
    assert_nil data_export.resources.find_by(resource_type: :call, resource_id: private_call.id)
    assert_nil data_export.resources.find_by(resource_type: :note, resource_id: private_note.id)
    assert_nil data_export.resources.find_by(resource_type: :call_recording, resource_id: private_call.recordings.first.id)
  end

  test "cleanup deletes the full export prefix from private storage" do
    data_export = create(:data_export, subject: create(:organization), zip_path: "some/zip/path.zip")
    id = data_export.id
    first_object = mock("first object")
    second_object = mock("second object")
    first_object.expects(:delete)
    second_object.expects(:delete)
    bucket = mock("export bucket")
    bucket.expects(:objects).with(prefix: data_export.export_prefix).returns([first_object, second_object])
    data_export.stubs(:export_bucket).returns(bucket)

    data_export.cleanup!

    assert_nil DataExport.find_by(id: id)
  end

  test "presigns only a completed archive for five minutes" do
    data_export = create(:data_export, :completed, zip_path: nil)
    data_export.update!(zip_path: data_export.expected_zip_path)
    archive = mock("archive")
    archive.expects(:presigned_url).with(
      :get,
      expires_in: 5.minutes.to_i,
      response_content_disposition: %(attachment; filename="#{data_export.download_filename}"),
      response_content_type: "application/zip",
    ).returns("http://s3.camp.home/signed")
    bucket = mock("export bucket")
    bucket.expects(:object).with(data_export.expected_zip_path).returns(archive)
    data_export.stubs(:export_bucket).returns(bucket)

    assert_equal "http://s3.camp.home/signed", data_export.presigned_download_url
  end

  test "does not presign an incomplete export" do
    data_export = create(:data_export, status: :archiving, zip_path: nil)

    assert_raises(ActiveRecord::RecordNotFound) { data_export.presigned_download_url }
  end

  test "uses the authenticated API route for the download email" do
    data_export = create(:data_export, :completed)

    assert_equal(
      "http://api.campsite.test:3000/v1/organizations/#{data_export.member.organization.slug}/data_exports/#{data_export.public_id}/download",
      data_export.zip_url,
    )
  end

  test "creates resources for user's posts" do
    viewer = create(:organization_membership)
    org = viewer.organization
    data_export = create(:data_export, subject: viewer, member: viewer)

    project = create(:project, organization: org)
    viewer_post = create(:post, project: project, member: viewer)
    other_post = create(:post, project: project)

    private_project = create(:project, organization: org, private: true)
    viewer_private_post = create(:post, project: private_project, member: viewer)
    other_private_post = create(:post, project: private_project)

    assert_difference -> { DataExportResource.count }, 5 do
      data_export.create_resources
    end

    assert_not_nil data_export.resources.find_by(resource_type: :member)
    assert_not_nil data_export.resources.find_by(resource_type: :post, resource_id: viewer_post.id)
    assert_not_nil data_export.resources.find_by(resource_type: :post, resource_id: viewer_private_post.id)
    assert_not_nil data_export.resources.find_by(resource_type: :project, resource_id: project.id)
    assert_not_nil data_export.resources.find_by(resource_type: :project, resource_id: private_project.id)

    assert_nil data_export.resources.find_by(resource_type: :post, resource_id: other_post.id)
    assert_nil data_export.resources.find_by(resource_type: :call, resource_id: other_private_post.id)
  end
end
