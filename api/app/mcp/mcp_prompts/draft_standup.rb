# frozen_string_literal: true

module McpPrompts
  # Summarize the user's recent activity into a standup-style status update. Reads
  # via existing tools; writes nothing (drafting the post is left to the user).
  class DraftStandup < McpPrompt
    prompt_name "draft_standup"
    title "Draft a standup update"
    description "Summarize your recent Campsite posts and comments into a Done / In progress / Blocked status update."
    arguments [
      org_slug_arg,
      arg("since", description: "How far back to look, e.g. \"last 7 days\", \"this week\", or an ISO date like 2026-06-23. Defaults to the last week."),
    ]

    def self.template(args)
      org = args["org_slug"]
      since = args["since"].presence || "the last 7 days"

      user_message_result(<<~TEXT.strip)
        Draft a standup update for me from my Campsite activity in `#{org}` over #{since}.

        1. Call `whoami` to confirm who I am, then use `list_posts` and `search_posts` for `#{org}` to find the posts I authored or commented on in that window. Use `read_post` to pull detail where a title alone isn't enough.
        2. Synthesize a concise standup with three sections — **Done**, **In progress**, and **Blocked / needs input** — as short bullet points, each linking the relevant post by title.
        3. Keep it factual and grounded in what you actually found; don't invent work that isn't in the activity.

        Return the draft as plain text for me to review. Do not create a post or comment unless I explicitly ask you to.
      TEXT
    end
  end
end
