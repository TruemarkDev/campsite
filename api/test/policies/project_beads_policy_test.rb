# frozen_string_literal: true

require "test_helper"

class ProjectBeadsPolicyTest < ActiveSupport::TestCase
  setup do
    @admin = create(:organization_membership, :admin)
    @project = create(:project, organization: @admin.organization, creator: @admin)
  end

  test "source management requires explicit kept human membership" do
    assert_not ProjectPolicy.new(@admin.user, @project).manage_beads_source?

    @project.add_member!(@admin)
    assert ProjectPolicy.new(@admin.user, @project).manage_beads_source?

    @project.remove_member!(@admin)
    assert_not ProjectPolicy.new(@admin.user, @project).manage_beads_source?
  end

  test "board read rejects broad public visibility and permits explicit guest membership" do
    assert_not ProjectPolicy.new(@admin.user, @project).read_beads_board?

    guest = create(:organization_membership, :guest, organization: @admin.organization)
    @project.add_member!(guest)
    assert ProjectPolicy.new(guest.user, @project).read_beads_board?
  end

  test "board read permits only an attached kept oauth application" do
    application = create(:oauth_application, owner: @admin.organization)
    actor = ApiActor.new(oauth_application: application)
    assert_not ProjectPolicy.new(actor, @project).read_beads_board?

    @project.add_oauth_application!(application)
    assert ProjectPolicy.new(actor, @project).read_beads_board?

    @project.remove_oauth_application!(application)
    assert_not ProjectPolicy.new(actor, @project).read_beads_board?
  end
end
