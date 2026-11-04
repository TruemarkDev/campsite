# frozen_string_literal: true

module McpTools
  # Creates a follow-up (a personal reminder to resurface a post, note, or comment)
  # for the acting member. Mirrors the Api::V1::{Posts,Notes,Comments}::FollowUpsController
  # #create endpoints.
  #
  # Scope note: although this writes (a `follow_up` row), it is DELIBERATELY gated by
  # the `mcp` scope alone — no `write_*` scope. A follow-up is the acting member's OWN
  # personal reminder to revisit something later; it is never an assignment to another
  # member and exposes/changes no shared content. The mirrored REST endpoints likewise
  # carry no OAuth write scope. This exemption is intentional and explicit (not an
  # oversight); a read-only loop connector can set reminders for itself without
  # requesting a content-write grant.
  class CreateFollowUp < McpTool
    tool_name "create_follow_up"
    description "Set a personal follow-up reminder on a post, note, or comment for the connected user. " \
      "The item resurfaces in your inbox at show_at."
    input_schema(org_scoped_schema(
      properties: {
        subject_type: { type: "string", enum: ["post", "note", "comment"], description: "Whether to follow up on a 'post', 'note', or 'comment'." },
        subject_id: { type: "string", description: "The public id of the post, note, or comment to follow up on." },
        show_at: { type: "string", description: "ISO8601 time when the follow-up should resurface, e.g. 2026-07-01T09:00:00Z." },
      },
      required: ["subject_type", "subject_id", "show_at"],
    ))

    private

    def execute
      actor, organization, member = organization_context!

      subject = load_subject(organization)
      authorize!(actor, subject, :create_follow_up?)

      follow_up = subject.follow_ups.create!(
        organization_membership: member,
        show_at: input[:show_at],
      )

      Notification.discard_home_inbox_notifications(
        member: member,
        follow_up_subject: subject,
      )

      data_response(serialize(FollowUpSerializer, follow_up, organization: organization, member: member))
    end

    def load_subject(organization)
      case input[:subject_type]
      when "post"
        organization.kept_published_posts.find_by!(public_id: input[:subject_id])
      when "note"
        organization.notes.kept.find_by!(public_id: input[:subject_id])
      when "comment"
        comment = Comment.kept.preload(:subject).find_by!(public_id: input[:subject_id])
        raise ActiveRecord::RecordNotFound if comment.organization != organization

        comment
      else
        raise ToolError, "subject_type must be 'post', 'note', or 'comment'."
      end
    end
  end
end
