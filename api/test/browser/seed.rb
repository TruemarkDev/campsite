# frozen_string_literal: true

raise "Browser fixture runner required" unless ENV["CAMPSITE_BROWSER_TEST"] == "1" && Rails.env.test?
raise "Wrong fixture database" unless ApplicationRecord.connection_db_config.database == ENV.fetch("PG_TEST_DATABASE")
raise "Fixture database must be empty" if User.exists? || Organization.exists?

admin = FactoryBot.create(:user,
  name: "Browser Author", username: "browser_author", email: "author@example.test",
  password: ENV.fetch("BROWSER_TEST_PASSWORD"))
organization = FactoryBot.create(:organization, :pro,
  creator: admin, name: "Browser Fixtures", slug: "browser-fixtures")
member = FactoryBot.create(:organization_membership, :admin, organization: organization, user: admin)
project = Project.create!(organization: organization, creator: member, name: "General", is_general: true, is_default: true)
FactoryBot.create(:project_membership, project: project, organization_membership: member)
viewer = FactoryBot.create(:user,
  name: "Browser Viewer", username: "browser_viewer", email: "viewer@example.test",
  password: ENV.fetch("BROWSER_TEST_PASSWORD"))
viewer_member = FactoryBot.create(:organization_membership, :member, organization: organization, user: viewer)
FactoryBot.create(:project_membership, project: project, organization_membership: viewer_member)
FactoryBot.create(:note, member: member, public_id: "pwprivate001", title: "Private fixture note", description_html: "<p>Private fixture content</p>")
shared_note = FactoryBot.create(:note, member: member, public_id: "pwshared0001", title: "Read-only fixture note", description_html: "<p>Read-only fixture content</p>")
FactoryBot.create(:permission, subject: shared_note, user: viewer, action: :view, event_actor: member)
revoked_note = FactoryBot.create(:note, member: member, public_id: "pwrevoked001", title: "Revocation fixture note", description_html: "<p>Revocation fixture content</p>")
FactoryBot.create(:permission, subject: revoked_note, user: viewer, action: :view, event_actor: member, public_id: "pwrevokeperm")
FactoryBot.create(:post, :with_poll, member: member, organization: organization, project: project, public_id: "pwpoll000001", title: "Existing poll fixture")
puts "Browser fixtures created"
