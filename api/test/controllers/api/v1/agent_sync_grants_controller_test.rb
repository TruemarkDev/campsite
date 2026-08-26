# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class AgentSyncGrantsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @note = create(:note, description_html: "<p>Before</p>", description_state: "initial-state", description_schema_version: 9)
        @grant, @token = AgentSyncGrant.issue!(
          note: @note,
          organization_membership: @note.member,
          actor_id: "summary-agent",
          actor_name: "Summary agent",
        )
        @headers = { "Authorization" => "Bearer #{@token}" }
      end

      test "verifies a bearer grant and returns only its bounded identity" do
        post verify_agent_sync_grant_path, params: { note_id: @note.public_id }, headers: @headers, as: :json

        assert_response :ok
        assert_response_gen_schema
        assert_equal @grant.public_id, json_response["grant_id"]
        assert_equal @note.public_id, json_response["note_id"]
        assert_equal "summary-agent", json_response["actor_id"]
        assert_equal @note.member.public_id, json_response["invoked_by"]
      end

      test "requires an exact bearer token for the requested note" do
        post verify_agent_sync_grant_path, params: { note_id: @note.public_id }, headers: { "Authorization" => @token }, as: :json
        assert_response :unauthorized

        post verify_agent_sync_grant_path, params: { note_id: create(:note).public_id }, headers: @headers, as: :json
        assert_response :unauthorized
      end

      test "reads and writes only the granted note sync state" do
        get agent_sync_grant_state_path(@note.public_id), headers: @headers, as: :json

        assert_response :ok
        assert_equal "initial-state", json_response["description_state"]

        put(
          agent_sync_grant_state_path(@note.public_id),
          params: {
            description_html: "<p>After</p>",
            description_state: "updated-state",
            description_schema_version: 9,
          },
          headers: @headers,
          as: :json,
        )

        assert_response :ok
        assert_equal "<p>After</p>", @note.reload.description_html
        assert_equal "updated-state", @note.description_state
        assert_equal "updated-state", json_response["description_state"]
      end

      test "initializes an absent Yjs state only once" do
        @note.update!(description_state: nil)

        put(
          agent_sync_grant_state_path(@note.public_id),
          params: {
            description_html: "<p>First</p>",
            description_state: "first-lineage",
            description_schema_version: 9,
            initialize: true,
          },
          headers: @headers,
          as: :json,
        )

        assert_response :ok
        assert_equal "first-lineage", json_response["description_state"]

        put(
          agent_sync_grant_state_path(@note.public_id),
          params: {
            description_html: "<p>Second</p>",
            description_state: "second-lineage",
            description_schema_version: 9,
            initialize: true,
          },
          headers: @headers,
          as: :json,
        )

        assert_response :ok
        assert_equal "first-lineage", json_response["description_state"]
        assert_equal "first-lineage", @note.reload.description_state
        assert_equal "<p>First</p>", @note.description_html
      end

      test "rejects stale state and a revoked token" do
        put(
          agent_sync_grant_state_path(@note.public_id),
          params: {
            description_html: "<p>Stale</p>",
            description_state: "stale-state",
            description_schema_version: 8,
          },
          headers: @headers,
          as: :json,
        )

        assert_response :unprocessable_entity
        assert_equal "stale_schema", json_response["code"]

        @grant.revoke!
        get agent_sync_grant_state_path(@note.public_id), headers: @headers, as: :json
        assert_response :unauthorized
      end

      test "records an agent proposal attribution without exposing a human token" do
        assert_difference -> { @note.timeline_events.note_suggestion_proposed_action.count }, 1 do
          post(
            "/v1/agent-sync-grants/notes/#{@note.public_id}/attributions",
            params: { batch_id: "batch-1", instruction: "Summarize" },
            headers: @headers,
            as: :json,
          )
        end

        assert_response :created
        event = @note.timeline_events.note_suggestion_proposed_action.last!
        assert_equal "batch-1", event.note_suggestion_batch_id
        assert_equal "Summary agent", event.note_suggestion_actor_name
        assert_equal @note.member, event.actor
      end
    end
  end
end
