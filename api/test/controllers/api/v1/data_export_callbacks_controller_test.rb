# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class DataExportCallbacksControllerTest < ActionDispatch::IntegrationTest
      include Devise::Test::IntegrationHelpers

      context "#update" do
        test "completes data export" do
          data_export = create(:data_export)

          put data_export_callback_path(data_export.public_id, zip_path: data_export.expected_zip_path),
            headers: { "X-Campsite-Export-Token" => data_export.callback_token }

          assert_response :ok

          assert_predicate data_export.reload, :completed?
          assert_not_nil data_export.completed_at
          assert_equal data_export.expected_zip_path, data_export.zip_path
          assert_enqueued_email_with OrganizationMailer, :data_export_completed, args: [data_export]
          assert_enqueued_sidekiq_job DataExportCleanupJob, args: [data_export.id]
        end


        test "rejects a callback without a bearer token" do
          data_export = create(:data_export)

          put data_export_callback_path(data_export.public_id, zip_path: data_export.expected_zip_path)

          assert_response :unauthorized
          assert_not_predicate data_export.reload, :completed?
        end

        test "rejects a callback token issued for another export" do
          data_export = create(:data_export)
          other_export = create(:data_export)

          put data_export_callback_path(data_export.public_id, zip_path: data_export.expected_zip_path),
            headers: { "X-Campsite-Export-Token" => other_export.callback_token }

          assert_response :unauthorized
          assert_not_predicate data_export.reload, :completed?
        end

        test "rejects an unexpected S3 path" do
          data_export = create(:data_export)

          put data_export_callback_path(data_export.public_id, zip_path: "exports/other/export.zip"),
            headers: { "X-Campsite-Export-Token" => data_export.callback_token }

          assert_response :unprocessable_entity
          assert_not_predicate data_export.reload, :completed?
        end

        test "rejects a replay after completing an export" do
          data_export = create(:data_export)
          token = data_export.callback_token
          headers = { "X-Campsite-Export-Token" => token }

          put data_export_callback_path(data_export.public_id, zip_path: data_export.expected_zip_path), headers: headers
          assert_response :ok

          put data_export_callback_path(data_export.public_id, zip_path: data_export.expected_zip_path), headers: headers

          assert_response :conflict
        end
      end
    end
  end
end
