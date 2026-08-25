# frozen_string_literal: true

require "test_helper"

class AgentSyncGrantTest < ActiveSupport::TestCase
  setup do
    @note = create(:note)
    @member = @note.member
  end

  test "issues and authenticates a note-scoped write grant" do
    grant, token = AgentSyncGrant.issue!(
      note: @note,
      organization_membership: @member,
      actor_id: "summary-agent",
      actor_name: "Summary agent",
    )

    assert_equal grant, AgentSyncGrant.authenticate(token: token, note_public_id: @note.public_id)
    assert_equal [AgentSyncGrant::WRITE_SCOPE], grant.scopes
    assert_operator grant.expires_at, :<=, AgentSyncGrant::MAX_LIFETIME.from_now
  end

  test "rejects a grant for another note" do
    _grant, token = AgentSyncGrant.issue!(
      note: @note,
      organization_membership: @member,
      actor_id: "summary-agent",
      actor_name: "Summary agent",
    )

    assert_nil AgentSyncGrant.authenticate(token: token, note_public_id: create(:note).public_id)
  end

  test "rejects revoked, expired, and malformed grants" do
    grant, token = AgentSyncGrant.issue!(
      note: @note,
      organization_membership: @member,
      actor_id: "summary-agent",
      actor_name: "Summary agent",
    )
    grant.revoke!

    assert_nil AgentSyncGrant.authenticate(token: token, note_public_id: @note.public_id)
    assert_nil AgentSyncGrant.authenticate(token: "not-a-token", note_public_id: @note.public_id)

    expired_grant, expired_token = AgentSyncGrant.issue!(
      note: @note,
      organization_membership: @member,
      actor_id: "expired-agent",
      actor_name: "Expired agent",
    )
    expired_grant.update_column(:expires_at, 1.minute.ago)

    assert_nil AgentSyncGrant.authenticate(token: expired_token, note_public_id: @note.public_id)
  end

  test "caps lifetime and requires a membership in the note organization" do
    grant, = AgentSyncGrant.issue!(
      note: @note,
      organization_membership: @member,
      actor_id: "summary-agent",
      actor_name: "Summary agent",
      expires_in: 1.day,
    )

    assert_in_delta AgentSyncGrant::MAX_LIFETIME.from_now, grant.expires_at, 2.seconds

    assert_raises ActiveRecord::RecordInvalid do
      AgentSyncGrant.issue!(
        note: @note,
        organization_membership: create(:organization_membership),
        actor_id: "summary-agent",
        actor_name: "Summary agent",
      )
    end
  end
end
