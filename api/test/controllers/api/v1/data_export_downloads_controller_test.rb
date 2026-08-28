# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class DataExportDownloadsControllerTest < ActionDispatch::IntegrationTest
      include Devise::Test::IntegrationHelpers

      setup do
        @member = create(:organization_membership)
        @organization = @member.organization
        @data_export = create(
          :data_export,
          :completed,
          member: @member,
          subject: @organization,
          zip_path: "exports/export-id/export.zip",
        )
      end

      test "redirects the requester to a short-lived archive URL" do
        DataExport.any_instance.expects(:presigned_download_url).returns("http://s3.camp.home/signed-export")
        sign_in @member.user

        get organization_data_export_download_path(@organization.slug, @data_export.public_id)

        assert_redirected_to "http://s3.camp.home/signed-export"
      end

      test "forbids another organization member" do
        other_member = create(:organization_membership, organization: @organization)
        sign_in other_member.user

        get organization_data_export_download_path(@organization.slug, @data_export.public_id)

        assert_response :forbidden
      end

      test "rejects an unauthenticated request" do
        get organization_data_export_download_path(@organization.slug, @data_export.public_id)

        assert_response :unauthorized
      end

      test "does not expose an incomplete export" do
        @data_export.update!(status: :archiving, completed_at: nil)
        sign_in @member.user

        get organization_data_export_download_path(@organization.slug, @data_export.public_id)

        assert_response :not_found
      end
    end
  end
end
