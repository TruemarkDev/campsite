# frozen_string_literal: true

require "test_helper"
require_relative "../../../../test_helpers/oauth_test_helper"

module Api
  module V1
    module Projects
      class BeadsPublisherControllerTest < ActionDispatch::IntegrationTest
        include OauthTestHelper

        setup do
          @admin = create(:organization_membership, :admin)
          @organization = @admin.organization
          @project = create(:project, organization: @organization, creator: @admin)
          @project.add_member!(@admin)
          @application = create(:oauth_application, owner: @organization, creator: @admin)
          @project.add_oauth_application!(@application)
          @token = create(:access_token, resource_owner: @organization, application: @application)
          Flipper.enable(:channel_beads_board, @organization)
        end

        test "exact attached connector completes pairing and idempotently publishes" do
          _challenge, plaintext = ProjectBeadsPairingChallenge.issue!(project: @project, oauth_application: @application, organization_membership: @admin)

          post pairing_path,
            params: { challenge: plaintext, source_project_id: "campsite.board", repository_display_name: "Campsite" },
            headers: bearer_token_header(@token.plaintext_token),
            as: :json

          assert_response :ok
          source = @project.reload.project_beads_source
          payload = snapshot_payload(source)

          assert_difference -> { source.snapshots.count }, 1 do
            post snapshots_path, params: payload, headers: bearer_token_header(@token.plaintext_token), as: :json
            assert_response :ok
          end
          assert_no_difference -> { source.snapshots.count } do
            post snapshots_path, params: payload, headers: bearer_token_header(@token.plaintext_token), as: :json
            assert_response :ok
          end
        end

        test "another application cannot publish and archived projects retain last good snapshot" do
          source = create_source
          payload = snapshot_payload(source)
          other = create(:oauth_application, owner: @organization)
          @project.add_oauth_application!(other)
          other_token = create(:access_token, resource_owner: @organization, application: other)

          assert_no_difference -> { source.snapshots.count } do
            post snapshots_path, params: payload, headers: bearer_token_header(other_token.plaintext_token), as: :json
          end
          assert_response :forbidden

          @project.archive!(@admin)
          assert_no_difference -> { source.snapshots.count } do
            post snapshots_path, params: payload, headers: bearer_token_header(@token.plaintext_token), as: :json
          end
          assert_response :not_found
        end

        private

        def create_source
          ProjectBeadsSource.create!(
            project: @project,
            oauth_application: @application,
            source_project_id: "campsite.board",
            repository_display_name: "Campsite",
            verified_at: Time.current,
          )
        end

        def pairing_path
          organization_project_beads_source_pairing_completion_path(@organization.slug, @project.public_id)
        end

        def snapshots_path
          organization_project_beads_source_snapshots_path(@organization.slug, @project.public_id)
        end

        def snapshot_payload(source)
          payload = {
            schema_version: 1,
            source_id: source.public_id,
            source_project_id: source.source_project_id,
            beads_version: "1.2.2",
            beads_schema_version: "1",
            branch: "main",
            revision: "abc123",
            collected_at: Time.current.utc.iso8601(3),
            issues: [],
          }
          payload[:digest] = Digest::SHA256.hexdigest(ProjectBeadsSnapshotSchema.canonical_json(payload.deep_stringify_keys))
          payload
        end
      end
    end
  end
end
