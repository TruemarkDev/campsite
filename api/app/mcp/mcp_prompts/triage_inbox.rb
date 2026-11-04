# frozen_string_literal: true

module McpPrompts
  # Walk the user's notifications, summarize what needs attention, and propose
  # follow-ups — all via existing tools. Mutates nothing itself.
  class TriageInbox < McpPrompt
    prompt_name "triage_inbox"
    title "Triage my inbox"
    description "Summarize your Campsite notifications and suggest follow-ups for items that need action."
    arguments [
      org_slug_arg,
      arg("filter", description: "Optional notifications filter (e.g. \"unread\", \"home\", \"activity\")."),
    ]

    def self.template(args)
      org = args["org_slug"]
      filter = args["filter"].presence

      filter_clause =
        if filter
          " using the `#{filter}` filter"
        else
          " (start with the unread ones)"
        end

      user_message_result(<<~TEXT.strip)
        Triage my Campsite inbox for the organization `#{org}`.

        1. Call `list_notifications` for `#{org}`#{filter_clause}, paging until you have a complete picture.
        2. Group the notifications by what they are about (post, comment, mention, follow-up) and summarize the ones that need my attention, newest and most important first. Use `read_post` or `read_messages` to add context only where a notification is ambiguous.
        3. For anything that needs a reply or action I can't take right now, propose a follow-up: call `create_follow_up` with the subject and a sensible `show_at` time, and tell me what you queued.
        4. End with a short, prioritized list of what I should look at myself.

        Do not resolve, reply to, or edit anything without asking me first — this is a read-and-summarize pass.
      TEXT
    end
  end
end
