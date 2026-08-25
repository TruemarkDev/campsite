# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Notes
      class AgentSyncGrantsControllerTest < ActionDispatch::IntegrationTest
        include Devise::Test::IntegrationHelpers

        setup do
          @note = create(:note)
          @member = @note.member
          @organization = @member.organization
          @params = { actor_id: "summary-agent", actor_name: "Summary agent", expires_in: 600 }
          sign_in @member.user
        end

        test "issues a short-lived grant to an editor while enabled" do
          Flipper.enable(:ai_note_editing, @organization)

          assert_difference -> { AgentSyncGrant.count }, 1 do
            post organization_note_agent_sync_grants_path(@organization.slug, @note.public_id), params: @params, as: :json
          end

          assert_response :created
          assert_response_gen_schema
          assert_predicate json_response["token"], :present?
          assert_equal json_response["id"], AgentSyncGrant.last.public_id
          assert_equal @note, AgentSyncGrant.authenticate(token: json_response["token"], note_public_id: @note.public_id).note
        end

        test "is unavailable while the feature is disabled" do
          assert_no_difference -> { AgentSyncGrant.count } do
            post organization_note_agent_sync_grants_path(@organization.slug, @note.public_id), params: @params, as: :json
          end

          assert_response :not_found
        end

        test "requires note edit permission" do
          viewer = create(:organization_membership, :member, organization: @organization)
          create(:permission, user: viewer.user, subject: @note, action: :view)
          sign_in viewer.user
          Flipper.enable(:ai_note_editing, @organization)

          post organization_note_agent_sync_grants_path(@organization.slug, @note.public_id), params: @params, as: :json

          assert_response :forbidden
        end

        test "revokes an existing grant" do
          grant, = AgentSyncGrant.issue!(note: @note, organization_membership: @member, actor_id: "agent", actor_name: "Agent")

          delete organization_note_agent_sync_grant_path(@organization.slug, @note.public_id, grant.public_id), as: :json

          assert_response :no_content
          assert_predicate grant.reload, :revoked_at?
        end
      end
    end
  end
end
