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
            params: pairing_payload(plaintext),
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

        test "pairing is bound to its channel and rejects an archived channel" do
          challenge, plaintext = ProjectBeadsPairingChallenge.issue!(project: @project, oauth_application: @application, organization_membership: @admin)
          other_project = create(:project, organization: @organization, creator: @admin)
          other_project.add_oauth_application!(@application)

          assert_no_difference -> { ProjectBeadsSource.count } do
            post organization_project_beads_source_pairing_completion_path(@organization.slug, other_project.public_id),
              params: pairing_payload(plaintext),
              headers: bearer_token_header(@token.plaintext_token),
              as: :json
            assert_response :not_found
          end
          assert_nil challenge.reload.consumed_at

          @project.archive!(@admin)
          assert_no_difference -> { ProjectBeadsSource.count } do
            post pairing_path,
              params: pairing_payload(plaintext),
              headers: bearer_token_header(@token.plaintext_token),
              as: :json
            assert_response :not_found
          end
          assert_nil challenge.reload.consumed_at
        end

        test "pairing requires workspace metadata and keeps challenges single use" do
          challenge, plaintext = ProjectBeadsPairingChallenge.issue!(project: @project, oauth_application: @application, organization_membership: @admin)
          assert_not_equal plaintext, challenge.token_digest

          post pairing_path, params: pairing_payload(plaintext).except(:revision), headers: bearer_token_header(@token.plaintext_token), as: :json
          assert_response :unprocessable_entity
          assert_nil challenge.reload.consumed_at

          post pairing_path, params: pairing_payload(plaintext), headers: bearer_token_header(@token.plaintext_token), as: :json
          assert_response :ok
          assert_not_nil challenge.reload.consumed_at

          assert_no_difference -> { ProjectBeadsSource.count } do
            post pairing_path, params: pairing_payload(plaintext), headers: bearer_token_header(@token.plaintext_token), as: :json
            assert_response :not_found
          end
        end

        test "expired challenge or revoked initiator cannot replace last good source" do
          source = create_source
          snapshot = ProjectBeadsSnapshot.ingest!(source: source, attributes: snapshot_payload(source))
          challenge, plaintext = ProjectBeadsPairingChallenge.issue!(project: @project, oauth_application: @application, organization_membership: @admin)
          challenge.update!(expires_at: 1.minute.ago)
          post pairing_path, params: pairing_payload(plaintext), headers: bearer_token_header(@token.plaintext_token), as: :json
          assert_response :not_found
          assert_equal snapshot, source.reload.current_snapshot

          challenge.update!(expires_at: 1.minute.from_now)
          @project.remove_member!(@admin)
          post pairing_path, params: pairing_payload(plaintext), headers: bearer_token_header(@token.plaintext_token), as: :json
          assert_response :forbidden
          assert_nil challenge.reload.consumed_at
          assert_equal snapshot, source.reload.current_snapshot
        end

        test "verified replacement clears prior snapshots atomically" do
          source = create_source
          snapshot = ProjectBeadsSnapshot.ingest!(source: source, attributes: snapshot_payload(source))
          challenge, plaintext = ProjectBeadsPairingChallenge.issue!(project: @project, oauth_application: @application, organization_membership: @admin)

          assert_equal snapshot, source.reload.current_snapshot
          post pairing_path, params: pairing_payload(plaintext).merge(source_project_id: "replacement.board"), headers: bearer_token_header(@token.plaintext_token), as: :json
          assert_response :ok
          assert_equal "replacement.board", source.reload.source_project_id
          assert_nil source.current_snapshot
          assert_not ProjectBeadsSnapshot.exists?(snapshot.id)
          assert_not_nil challenge.reload.consumed_at
        end

        test "detached connector and disabled feature cannot publish" do
          source = create_source
          payload = snapshot_payload(source)
          @project.remove_oauth_application!(@application)
          post snapshots_path, params: payload, headers: bearer_token_header(@token.plaintext_token), as: :json
          assert_response :forbidden
          assert_nil source.reload.current_snapshot

          @project.add_oauth_application!(@application)
          Flipper.disable(:channel_beads_board, @organization)
          post snapshots_path, params: payload, headers: bearer_token_header(@token.plaintext_token), as: :json
          assert_response :not_found
          assert_nil source.reload.current_snapshot
        end

        test "attached oauth applications can read the safe current board" do
          source = create_source
          other = create(:oauth_application, owner: @organization)
          @project.add_oauth_application!(other)
          token = create(:access_token, resource_owner: @organization, application: other)
          path = organization_project_beads_source_snapshot_path(@organization.slug, @project.public_id)

          get path, headers: bearer_token_header(token.plaintext_token), as: :json
          assert_response :ok
          assert_response_gen_schema
          assert_equal source.public_id, json_response.fetch("source_id")
          assert_equal %w[avatar_url avatar_urls id name roles status], json_response.fetch("agents").first.keys.sort

          @project.remove_oauth_application!(other)
          get path, headers: bearer_token_header(token.plaintext_token), as: :json
          assert_response :forbidden
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

        def pairing_payload(challenge)
          { challenge: challenge, source_project_id: "campsite.board", repository_display_name: "Campsite", beads_version: "1.2.2", branch: "main", revision: "abc123" }
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
