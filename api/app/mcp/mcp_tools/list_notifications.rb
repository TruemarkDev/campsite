# frozen_string_literal: true

module McpTools
  # Lists the connected user's notifications in an organization — their inbox by
  # default, or their activity feed. Mirrors Api::V1::NotificationsController#index.
  class ListNotifications < McpTool
    tool_name "list_notifications"
    description "List the user's notifications in an organization, most recent first. " \
      "Defaults to the full inbox; filter: \"home\" = curated home inbox, \"activity\" = activity feed."
    input_schema(org_scoped_schema(
      properties: {
        unread: { type: "boolean", description: "Only return unread notifications." },
        filter: {
          type: "string",
          enum: ["home", "activity"],
          description: "Omit for the full inbox; \"home\" = curated home inbox; \"activity\" = activity feed.",
        },
      },
      paginated: true,
    ))

    private

    def execute
      _actor, organization, member = organization_context!

      notifications = case input[:filter]
      when "activity"
        member.kept_notifications.activity
      when "home"
        member.inbox_notifications.home_inbox
      else
        member.inbox_notifications
      end
      notifications = notifications.unread if input[:unread]

      page = paginate(notifications.serializer_preload, order: { created_at: :desc, id: :desc })
      data = serialize(NotificationPageSerializer, page, organization: organization, member: member)
      data_response(data)
    end
  end
end
