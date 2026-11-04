# frozen_string_literal: true

class UpdateMentionUsernamesJob < BaseJob
  sidekiq_options queue: "background"

  MENTION_LABEL_ACTOR_ID = "system:mention-labels"
  MENTION_LABEL_ACTOR_NAME = "Campsite"

  def perform(user_id)
    user = User.includes(organization_memberships: :organization).find(user_id)

    # example TipTap mention format:
    # <span data-type="mention" class="mention" data-id="y92bm4232unj" data-label="dumbledore">@dumbledore</span>
    # where the "data-id" attribute is the OrganizationMembership.public_id

    user.organization_memberships.each do |member|
      update_posts(user, member)
      update_comments(user, member)
      update_notes(user, member)
    end
  end

  private

  def update_posts(user, member)
    field = Post.arel_table[:description_html]
    posts = member.organization.posts.where(field.matches("%data-id=\"#{member.public_id}\"%"))
    posts.find_each do |post|
      doc = Nokogiri::HTML.fragment(post.description_html)
      post.update_column(:description_html, update_mentions(user, member, doc))
    end
  end

  def update_comments(user, member)
    field = Comment.arel_table[:body_html]
    comments = Comment.where(field.matches("%data-id=\"#{member.public_id}\"%"))
    comments.find_each do |comment|
      doc = Nokogiri::HTML.fragment(comment.body_html)
      comment.update_column(:body_html, update_mentions(user, member, doc))
    end
  end

  def update_notes(user, member)
    field = Note.arel_table[:description_html]
    notes = member.organization.notes.where(field.matches("%data-id=\"#{member.public_id}\"%"))
    notes.find_each do |note|
      grant, token = AgentSyncGrant.issue!(
        note: note,
        organization_membership: member,
        actor_id: MENTION_LABEL_ACTOR_ID,
        actor_name: MENTION_LABEL_ACTOR_NAME,
        scopes: [AgentSyncGrant::WRITE_SCOPE, AgentSyncGrant::MENTION_LABELS_SCOPE],
        expires_in: 5.minutes,
      )

      begin
        AgentNoteEditor.new(token).edit(
          note_id: note.public_id,
          mode: :direct,
          operation: {
            type: :update_mentions,
            membership_id: member.public_id,
            display_name: user.display_name,
            username: user.username,
          },
          schema_version: note.description_schema_version,
        )
      ensure
        grant.revoke!
      end
    end
  end

  def update_mentions(user, member, doc)
    nodes = doc.css("span[data-type=\"mention\"][data-id=\"#{member.public_id}\"]")
    nodes.each do |node|
      node["data-label"] = user.display_name
      node["data-username"] = user.username
      node.content = "@#{user.display_name}"
    end

    doc.to_s
  end
end
