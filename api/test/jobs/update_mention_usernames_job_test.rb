# frozen_string_literal: true

require "test_helper"

class UpdateMentionUsernamesJobTest < ActiveJob::TestCase
  context "perform" do
    test "updates posts" do
      member = create(:organization_membership, user: create(:user, username: "old_username", name: "Old Name"))
      post = create(:post, description_html: "<span data-type=\"mention\" class=\"mention\" data-id=\"#{member.public_id}\" data-label=\"Old Name\">@Old Name</span>", organization: member.organization)

      member.user.update!(name: "New Name")
      UpdateMentionUsernamesJob.new.perform(member.user.id)

      assert_equal "<span data-type=\"mention\" class=\"mention\" data-id=\"#{member.public_id}\" data-label=\"New Name\" data-username=\"old_username\">@New Name</span>", post.reload.description_html
    end

    test "updates comments" do
      member = create(:organization_membership, user: create(:user, username: "old_username", name: "Old Name"))
      comment = create(
        :comment,
        body_html: "<p>foo bar baz <span data-type=\"mention\" class=\"mention\" data-id=\"#{member.public_id}\" data-label=\"Old Name\">@Old Name</span></p>",
        subject: create(:post, organization: member.organization),
      )

      member.user.update!(name: "New Name")
      UpdateMentionUsernamesJob.new.perform(member.user.id)

      assert_equal "<p>foo bar baz <span data-type=\"mention\" class=\"mention\" data-id=\"#{member.public_id}\" data-label=\"New Name\" data-username=\"old_username\">@New Name</span></p>", comment.reload.body_html
    end

    test "updates notes" do
      member = create(:organization_membership, user: create(:user, username: "old_username", name: "Old Name"))
      note = create(
        :note,
        description_html: "<span data-type=\"mention\" class=\"mention\" data-id=\"#{member.public_id}\" data-label=\"Old Name\">@Old Name</span>",
        description_state: "existing-yjs-state",
        member: member,
      )

      AgentNoteEditor.any_instance.expects(:edit).with(
        note_id: note.public_id,
        mode: :direct,
        operation: {
          type: :update_mentions,
          membership_id: member.public_id,
          display_name: "New Name",
          username: "old_username",
        },
        schema_version: note.description_schema_version,
      )

      member.user.update!(name: "New Name")
      UpdateMentionUsernamesJob.new.perform(member.user.id)

      grant = note.agent_sync_grants.sole
      assert_equal [AgentSyncGrant::WRITE_SCOPE, AgentSyncGrant::MENTION_LABELS_SCOPE], grant.scopes
      assert_predicate grant, :revoked_at
      assert_equal "existing-yjs-state", note.reload.description_state
    end

    test "revokes the note-scoped grant and preserves state when sync fails" do
      member = create(:organization_membership, user: create(:user, username: "old_username", name: "Old Name"))
      note = create(
        :note,
        description_html: "<span data-type=\"mention\" data-id=\"#{member.public_id}\" data-label=\"Old Name\">@Old Name</span>",
        description_state: "existing-yjs-state",
        member: member,
      )

      AgentNoteEditor.any_instance.expects(:edit).raises(AgentNoteEditor::ConnectionFailedError)

      assert_raises(AgentNoteEditor::ConnectionFailedError) do
        UpdateMentionUsernamesJob.new.perform(member.user.id)
      end

      assert_equal "existing-yjs-state", note.reload.description_state
      assert_predicate note.agent_sync_grants.sole, :revoked_at
    end

    test "updates multiple mentions" do
      member = create(:organization_membership, user: create(:user, username: "old_username", name: "Old Name"))

      old_mention = "<span data-type=\"mention\" class=\"mention\" data-id=\"#{member.public_id}\" data-label=\"Old Name\">@Old Name</span>"

      post = create(:post, description_html: "<p>foo bar #{old_mention} and #{old_mention}</p>", organization: member.organization)

      member.user.update!(name: "New Name")
      UpdateMentionUsernamesJob.new.perform(member.user.id)

      new_mention = "<span data-type=\"mention\" class=\"mention\" data-id=\"#{member.public_id}\" data-label=\"New Name\" data-username=\"old_username\">@New Name</span>"

      assert_equal "<p>foo bar #{new_mention} and #{new_mention}</p>", post.reload.description_html
    end
  end
end
