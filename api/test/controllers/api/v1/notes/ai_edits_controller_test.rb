# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Notes
      class AiEditsControllerTest < ActionDispatch::IntegrationTest
        include Devise::Test::IntegrationHelpers

        setup do
          @note = create(:note)
          @member = @note.member
          @organization = @member.organization
          @params = {
            instruction: "make this concise",
            range: { from: 5, to: 17 },
            context: {
              selected_text: "verbose text",
              before: "Before ",
              after: " after",
            },
          }
          sign_in @member.user
        end

        test "returns a scoped structured edit for an editor" do
          Flipper.enable(:ai_note_editing, @organization)
          NoteAiEditor.any_instance.expects(:call).returns("concise text")

          post organization_note_ai_edits_path(@organization.slug, @note.public_id), params: @params, as: :json

          assert_response :ok
          assert_response_gen_schema
          assert_equal "replace_range", json_response.dig("operations", 0, "type")
          assert_equal "concise text", json_response.dig("operations", 0, "text")
          assert_equal "ai", json_response["actor_type"]
          assert_equal @member.public_id, json_response["invoked_by"]
          assert_equal @params[:instruction], json_response["instruction"]
          assert_predicate json_response["batch_id"], :present?
          event = @note.timeline_events.note_suggestion_proposed_action.last!
          assert_equal json_response["batch_id"], event.note_suggestion_batch_id
          assert_equal "Campsite AI", event.note_suggestion_actor_name
        end

        test "returns an insertion operation for an empty selection" do
          Flipper.enable(:ai_note_editing, @organization)
          NoteAiEditor.any_instance.stubs(:call).returns("Drafted text")
          @params[:range] = { from: 5, to: 5 }
          @params[:context][:selected_text] = ""

          post organization_note_ai_edits_path(@organization.slug, @note.public_id), params: @params, as: :json

          assert_response :ok
          assert_equal "insert_at_cursor", json_response.dig("operations", 0, "type")
        end

        test "is unavailable while the feature is disabled" do
          NoteAiEditor.any_instance.expects(:call).never

          post organization_note_ai_edits_path(@organization.slug, @note.public_id), params: @params, as: :json

          assert_response :not_found
        end

        test "requires note edit permission" do
          viewer = create(:organization_membership, :member, organization: @organization)
          create(:permission, user: viewer.user, subject: @note, action: :view)
          sign_in viewer.user
          Flipper.enable(:ai_note_editing, @organization)

          post organization_note_ai_edits_path(@organization.slug, @note.public_id), params: @params, as: :json

          assert_response :forbidden
        end

        test "rejects an invalid range without calling the provider" do
          Flipper.enable(:ai_note_editing, @organization)
          NoteAiEditor.any_instance.expects(:call).never
          @params[:range] = { from: 8, to: 4 }

          post organization_note_ai_edits_path(@organization.slug, @note.public_id), params: @params, as: :json

          assert_response :unprocessable_entity
          assert_equal "invalid_ai_edit", json_response["code"]
        end

        test "rate limits repeated requests per organization member" do
          Flipper.enable(:ai_note_editing, @organization)
          Rails.cache.stubs(:increment).returns(AiEditsController::RATE_LIMIT + 1)
          NoteAiEditor.any_instance.expects(:call).never

          post organization_note_ai_edits_path(@organization.slug, @note.public_id), params: @params, as: :json

          assert_response :too_many_requests
          assert_equal "ai_edit_rate_limited", json_response["code"]
        end
      end
    end
  end
end
