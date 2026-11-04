# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Projects
      class BeadsBoardsControllerTest < ActionDispatch::IntegrationTest
        include Devise::Test::IntegrationHelpers

        setup do
          @admin = create(:organization_membership, :admin)
          @organization = @admin.organization
          @project = create(:project, organization: @organization, creator: @admin)
          @project.add_member!(@admin)
          @application = create(:oauth_application, owner: @organization, creator: @admin, agent_capable: true)
          @project.add_oauth_application!(@application)
          @source = ProjectBeadsSource.create!(
            project: @project,
            oauth_application: @application,
            source_project_id: "campsite.board",
            repository_display_name: "Campsite",
            verified_at: Time.current,
          )
          Flipper.enable(:channel_beads_board, @organization)
          @path = organization_project_beads_board_path(@organization.slug, @project.public_id)
        end

        test "explicit member receives only the safe board and roster projection" do
          sign_in @admin.user
          get @path

          assert_response :ok
          assert_response_gen_schema
          assert_equal @source.public_id, json_response.fetch("source_id")
          assert_equal ["Agent", "Beads publisher"], json_response.fetch("agents").first.fetch("roles")
          forbidden = %w[client_id client_secret redirect_uri webhooks description notes comments path credentials]
          forbidden.each { |field| assert_not_includes response.body, field }
        end

        test "broad public-channel member without explicit attachment is forbidden" do
          nonmember = create(:organization_membership, :admin, organization: @organization)
          sign_in nonmember.user

          get @path
          assert_response :forbidden
        end

        test "explicit guest can read but cannot start pairing" do
          guest = create(:organization_membership, :guest, organization: @organization)
          @project.add_member!(guest)
          sign_in guest.user

          get @path
          assert_response :ok
          post organization_project_beads_source_pairings_path(@organization.slug, @project.public_id), params: { oauth_application_id: @application.public_id }
          assert_response :forbidden
        end

        test "feature flag defaults closed" do
          Flipper.disable(:channel_beads_board, @organization)
          sign_in @admin.user

          get @path
          assert_response :not_found
        end

        test "unauthenticated reader is rejected" do
          get @path
          assert_response :unauthorized
        end
      end
    end
  end
end
