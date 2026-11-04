# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Search
      class ResourceMentionsControllerTest < ActionDispatch::IntegrationTest
        include Devise::Test::IntegrationHelpers

        setup do
          @user = create(:user, username: "foo_bar", name: "Foo Bar")
          @member = create(:organization_membership, :member, user: @user)
          @org = @member.organization
          @project = create(:project, organization: @org)

          @miss_post = create(:post, :search_document, organization: @org, description_html: "<p>match-post</p>", comments: [
            create(:comment, body_html: "<p>match-comment</p>"),
          ])
          @match_post = create(:post, :search_document, organization: @org, title: "match-post-title")
          @match_post_from_integration = create(:post, :search_document, :from_integration, organization: @org, title: "matchy-matchy")
          create(:post, :search_document, organization: @org, title: "other-post")

          call_room = create(:call_room, organization: @org)
          @match_call = create(:call, :search_document, room: call_room, title: "match-call", peers: [create(:call_peer, organization_membership: @member)], recordings: [create(:call_recording)])
          create(:call, :search_document, room: call_room, title: "other-call", peers: [create(:call_peer, organization_membership: @member)], recordings: [create(:call_recording)])

          @match_note = create(:note, :search_document, member: create(:organization_membership, organization: @org), project: @project, project_permission: :view, title: "match note")
          create(:note, :search_document, member: create(:organization_membership, organization: @org), project: @project, project_permission: :edit, title: "nope", description_html: "<p>match-note</p>")
          create(:note, :search_document, member: create(:organization_membership, organization: @org), project_permission: :none, title: "match-note")
          create(:note, :search_document, member: create(:organization_membership, organization: @org), project_permission: :none, title: "nope", description_html: "<p>match-note</p>")
        end


        context "#index" do
          test "fills the per-resource limit after filtering higher-ranked hidden notes" do
            visible_notes = Array.new(10) do |index|
              create(:note, :search_document, member: @member, project: @project, project_permission: :view, title: "r2regression visible #{index}")
            end
            hidden_note = create(:note, :search_document, member: create(:organization_membership, organization: @org), project_permission: :none, title: "r2regression")

            assert_equal hidden_note.id, Note.scoped_title_search(organization: @org, query: "r2regression").pluck(:id).fetch(0)

            sign_in @user
            get organization_search_resource_mentions_path(@org.slug, params: { q: "r2regression" })

            assert_response :ok
            assert_equal visible_notes.map(&:url).sort, json_response["items"].map { |item| item.dig("item", "id") }.sort
          end

          test "matches all results" do
            sign_in @user

            # Includes PostgreSQL candidate, count, and ranked search queries.
            assert_query_count 11 do
              get organization_search_resource_mentions_path(@org.slug, params: { q: "match" })
            end

            assert_response :ok
            assert_response_gen_schema

            matches = [@match_post, @match_post_from_integration, @match_call, @match_note]

            assert_equal 4, json_response["items"].size

            # the serializer/model uses the URL as the ID for normalization
            assert_equal matches.map(&:url).sort, json_response["items"].map { |item| item.dig("item", "id") }.sort
          end

          test "can return no results" do
            sign_in @user

            get organization_search_resource_mentions_path(@org.slug, params: { q: "zilch" })

            assert_response :ok
            assert_response_gen_schema

            assert_equal 0, json_response["items"].size
          end

          test "matches partial results" do
            sign_in @user

            get organization_search_resource_mentions_path(@org.slug, params: { q: "note" })

            assert_response :ok
            assert_response_gen_schema

            assert_equal 1, json_response["items"].size
            assert_equal @match_note.url, json_response["items"].first.dig("item", "id")
          end
        end
      end
    end
  end
end
