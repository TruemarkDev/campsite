# frozen_string_literal: true

class DataExport < ApplicationRecord
  class InvalidZipPath < StandardError; end

  DOWNLOAD_URL_LIFETIME = 5.minutes

  include PublicIdGenerator
  include MediaUrlBuilder
  include Rails.application.routes.url_helpers

  belongs_to :member, class_name: "OrganizationMembership"
  belongs_to :subject, polymorphic: true
  has_many :resources, class_name: "DataExportResource", dependent: :destroy

  enum :status, { pending: 0, archiving: 1, completed: 2, error: 3 }

  def perform
    create_resources
    queue_resource_jobs
  end

  def create_resources
    case subject_type
    when "Organization"
      create_org_users_resource
      create_org_projects_resource
    when "OrganizationMembership"
      create_org_membership_resource
    when "Project"
      create_org_project_resource
    end
  end

  def create_org_users_resource
    resources.find_or_create_by!(resource_type: "users")
  end

  def create_org_projects_resource
    subject.projects.not_private.find_each do |project|
      resources.find_or_create_by!(resource_type: "project", resource_id: project.id)
      create_org_posts_resource(project)
      create_org_notes_resource(project)
      create_org_calls_resource(project)
    end
  end

  def create_org_posts_resource(project)
    project.kept_published_posts
      .eager_load(:attachments, kept_comments: :attachments)
      .find_each(batch_size: 50) do |post|
      resources.find_or_create_by!(resource_type: "post", resource_id: post.id)
      create_post_attachments_resource(post)
    end
  end

  def create_post_attachments_resource(post)
    attachments = post.attachments.to_a + post.kept_comments.flat_map(&:attachments)
    attachments.each do |attachment|
      resources.find_or_create_by!(resource_type: "attachment", resource_id: attachment.id)
    end
  end

  def create_org_notes_resource(project)
    project.kept_notes
      .eager_load(:attachments, kept_comments: :attachments)
      .find_each(batch_size: 50) do |note|
      resources.find_or_create_by!(resource_type: "note", resource_id: note.id)
      create_org_note_attachments_resource(note)
    end
  end

  def create_org_note_attachments_resource(note)
    attachments = note.attachments.to_a + note.kept_comments.flat_map(&:attachments)
    attachments.each do |attachment|
      resources.find_or_create_by!(resource_type: "attachment", resource_id: attachment.id)
    end
  end

  def create_org_calls_resource(project)
    project.calls
      .eager_load(:recordings)
      .find_each do |call|
      resources.find_or_create_by!(resource_type: "call", resource_id: call.id)
      create_org_call_recordings_resource(call)
    end
  end

  def create_org_call_recordings_resource(call)
    call.recordings.each do |recording|
      resources.find_or_create_by!(resource_type: "call_recording", resource_id: recording.id)
    end
  end

  def create_org_membership_resource
    resources.find_or_create_by!(resource_type: "member", resource_id: subject.id)

    projects = []

    subject.kept_published_posts
      .eager_load(:attachments, kept_comments: :attachments)
      .find_each(batch_size: 50) do |post|
      resources.find_or_create_by!(resource_type: "post", resource_id: post.id)
      create_post_attachments_resource(post)
      projects << post.project
    end

    projects.uniq.compact.each do |project|
      resources.find_or_create_by!(resource_type: "project", resource_id: project.id)
    end
  end

  def create_org_project_resource
    resources.find_or_create_by!(resource_type: "project", resource_id: subject.id)
    create_org_posts_resource(subject)
    create_org_notes_resource(subject)
    create_org_calls_resource(subject)
  end

  def queue_resource_jobs
    resources.find_each.with_index do |resource, index|
      DataExportResourceJob.perform_in(0.1.seconds * index, resource.id)
    end
  end

  def check_completed
    archive = false
    cleanup = false

    with_lock do
      return unless pending?
      return if resources.pending.exists?

      if resources.error.exists?
        update!(status: :error)
        cleanup = true
      else
        Rails.logger.info("Data export #{public_id} resources completed, queueing archive")
        update!(status: :archiving)
        archive = true
      end
    end

    DataExportCleanupJob.perform_in(2.days, id) if cleanup
    DataExportArchiveJob.perform_async(id) if archive
  end

  def complete(zip_path)
    raise InvalidZipPath unless zip_path == expected_zip_path

    completed = with_lock do
      next false unless archiving?

      update!(zip_path: zip_path, completed_at: Time.current, status: :completed)
      true
    end

    return false unless completed

    OrganizationMailer.data_export_completed(self).deliver_later

    DataExportCleanupJob.perform_in(2.days, id)
    true
  end

  def fail!
    failed = with_lock do
      next false if completed? || error?

      update!(status: :error)
      true
    end

    DataExportCleanupJob.perform_in(2.days, id) if failed
    failed
  end

  def expected_zip_path
    "exports/#{public_id}/#{upload_name}.zip"
  end

  def zip_url
    base_url = Campsite.base_app_url

    organization_data_export_download_url(
      member.organization.slug,
      public_id,
      host: base_url.host,
      protocol: base_url.scheme,
      port: base_url.port,
      subdomain: Campsite.api_subdomain,
    )
  end

  def presigned_download_url
    raise ActiveRecord::RecordNotFound unless completed? && zip_path.present?

    export_bucket.object(zip_path).presigned_url(
      :get,
      expires_in: DOWNLOAD_URL_LIFETIME.to_i,
      response_content_disposition: %(attachment; filename="#{download_filename}"),
      response_content_type: "application/zip",
    )
  end

  def export_bucket
    DATA_EXPORT_BUCKET
  end

  def export_prefix
    "exports/#{public_id}/"
  end

  def cleanup_fragments!
    export_bucket.objects(prefix: export_prefix).each do |object|
      object.delete unless object.key == expected_zip_path
    end
  end

  def cleanup!
    export_bucket.objects(prefix: export_prefix).each(&:delete)
    destroy!
  end

  def upload_name
    case subject_type
    when "Organization"
      "export-#{subject.slug}-#{public_id}"
    when "OrganizationMembership"
      "export-#{subject.user.username}-#{public_id}"
    else
      public_id
    end
  end

  def download_filename
    "#{upload_name}.zip".gsub(/[^a-zA-Z0-9._-]/, "-")
  end
end
