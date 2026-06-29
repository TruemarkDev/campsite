# frozen_string_literal: true

module McpTools
  # Marks one of the user's own notifications (and the rest sharing its member and
  # target) as read. Mirrors Api::V1::Notifications::ReadsController#create.
  #
  # Scope note: although this writes (`read_at`), it is DELIBERATELY gated by the
  # `mcp` scope alone — no `write_*` scope — and lives among the read tools. The
  # mutation is self-only, idempotent, and exposes/destroys no content: it only
  # toggles the acting user's own inbox-read state, which is part of *using* the
  # inbox (`list_notifications`). The mirrored REST endpoint likewise carries no
  # OAuth write scope. This exemption is intentional and explicit (not an
  # oversight); a read-only loop connector can keep its own inbox tidy without
  # requesting a content-write grant.
  class MarkNotificationRead < McpTool
    tool_name "mark_notification_read"
    description "Mark one of your own notifications as read, by its public id."
    input_schema(org_scoped_schema(
      properties: {
        notification_id: { type: "string", description: "Public id of the notification to mark read." },
      },
      required: ["notification_id"],
    ))

    private

    def execute
      _actor, _organization, member = organization_context!

      notification = member.notifications.find_by!(public_id: input[:notification_id])
      notification.notifications_for_same_member_and_target.update_all(read_at: Time.current)

      data_response({ ok: true, notification_id: notification.public_id })
    end
  end
end
