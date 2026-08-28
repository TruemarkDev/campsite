# frozen_string_literal: true

require "fileutils"
require "tmpdir"

class DataExportArchiveJob < BaseJob
  class ArchiveFailed < StandardError; end
  class InvalidObjectPath < StandardError; end

  sidekiq_options queue: "exports", retry: 3

  sidekiq_retries_exhausted do |msg|
    DataExport.find_by(id: msg["args"].first)&.fail!
  end

  def perform(export_id)
    export = DataExport.find(export_id)

    if export.completed?
      export.cleanup_fragments!
      return
    end

    return if export.error?
    raise ArchiveFailed, "Data export #{export.public_id} is not ready for archiving" unless export.archiving?

    Dir.mktmpdir("campsite-data-export-") do |temporary_root|
      contents_path = File.join(temporary_root, "contents")
      archive_path = File.join(temporary_root, export.download_filename)
      FileUtils.mkdir_p(contents_path)

      download_fragments(export, contents_path)
      create_archive(contents_path, archive_path)
      upload_archive(export, archive_path)

      export.complete(export.expected_zip_path)
      export.cleanup_fragments! if export.completed?
    end
  end

  private

  def download_fragments(export, contents_path)
    fragments = export.export_bucket.objects(prefix: export.export_prefix).reject do |object|
      object.key == export.expected_zip_path
    end
    raise ArchiveFailed, "Data export #{export.public_id} has no fragments" if fragments.empty?

    fragments.each do |object|
      relative_path = object.key.delete_prefix(export.export_prefix)
      destination = File.expand_path(relative_path, contents_path)
      expected_root = "#{File.expand_path(contents_path)}/"
      raise InvalidObjectPath, object.key unless destination.start_with?(expected_root)

      FileUtils.mkdir_p(File.dirname(destination))
      object.get(response_target: destination)
    end
  end

  def create_archive(contents_path, archive_path)
    created = system("/usr/bin/zip", "-q", "-r", archive_path, ".", chdir: contents_path)
    raise ArchiveFailed, "zip exited unsuccessfully" unless created && File.exist?(archive_path)
  end

  def upload_archive(export, archive_path)
    File.open(archive_path, "rb") do |archive|
      export.export_bucket.object(export.expected_zip_path).put(
        body: archive,
        content_type: "application/zip",
        content_disposition: %(attachment; filename="#{export.download_filename}"),
      )
    end
  end
end
