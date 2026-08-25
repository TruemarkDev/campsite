# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Notes
      class SuggestionResolutionsControllerTest < ActionDispatch::IntegrationTest
        include Devise::Test::IntegrationHelpers

        setup do
          @note = create(:note)
          @member = @note.member
          sign_in @member.user
        end

        test "records an editor resolution in note activity" do
          assert_difference -> { @note.timeline_events.note_suggestion_resolved_action.count }, 1 do
            post(
              organization_note_suggestion_resolutions_path(@member.organization.slug, @note.public_id),
              params: { batch_id: "batch-1", resolution: "accept" },
              as: :json,
            )
          end

          assert_response :created
          event = @note.timeline_events.note_suggestion_resolved_action.last!
          assert_equal "batch-1", event.note_suggestion_batch_id
          assert_equal "accept", event.note_suggestion_resolution
          assert_equal @member, event.actor
        end

        test "requires edit permission" do
          viewer = create(:organization_membership, :member, organization: @member.organization)
          create(:permission, user: viewer.user, subject: @note, action: :view)
          sign_in viewer.user

          post(
            organization_note_suggestion_resolutions_path(@member.organization.slug, @note.public_id),
            params: { batch_id: "batch-1", resolution: "reject" },
            as: :json,
          )

          assert_response :forbidden
        end
      end
    end
  end
end
