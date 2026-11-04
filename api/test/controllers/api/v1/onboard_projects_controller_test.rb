# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class OnboardProjectsControllerTest < ActionDispatch::IntegrationTest
      include Devise::Test::IntegrationHelpers

      setup do
        @member = create(:organization_membership)
        @org = @member.organization
        create(:project, name: "General", organization: @org, is_general: true, is_default: true)
      end

      context "#create" do
        test "creates projects and updates general project" do
          sign_in @member.user

          assert_difference -> { Project.count }, 2 do
            post organization_onboard_projects_path(@org.slug),
              params: {
                general_name: "Foo Bar",
                general_accessory: "📈",
                projects: [
                  { name: "Project 1", accessory: "🏕️" },
                  { name: "Project 2", accessory: "🧑‍🍳" },
                ],
              }
          end

          assert_response :no_content

          assert_equal "Foo Bar", @org.general_project.name
          assert_equal "📈", @org.general_project.accessory
          created_projects = @org.projects.where.not(id: @org.general_project.id).index_by(&:name)
          assert_equal ["Project 1", "Project 2"], created_projects.keys.sort
          assert_equal "🏕️", created_projects.fetch("Project 1").accessory
          assert_equal "🧑‍🍳", created_projects.fetch("Project 2").accessory
        end

        test "return 403 for a random user" do
          sign_in create(:user)

          assert_difference -> { Project.count }, 0 do
            post organization_onboard_projects_path(@org.slug),
              params: {
                general_name: "Foo Bar",
                general_accessory: "📈",
                projects: [
                  { name: "Project 1", accessory: "🏕️" },
                  { name: "Project 2", accessory: "🧑‍🍳" },
                ],
              }
          end

          assert_response :forbidden
        end

        test "returns 401 for unauthorized user" do
          assert_difference -> { Project.count }, 0 do
            post organization_onboard_projects_path(@org.slug),
              params: {
                general_name: "Foo Bar",
                general_accessory: "📈",
                projects: [
                  { name: "Project 1", accessory: "🏕️" },
                  { name: "Project 2", accessory: "🧑‍🍳" },
                ],
              }
          end

          assert_response :unauthorized
        end
      end
    end
  end
end
