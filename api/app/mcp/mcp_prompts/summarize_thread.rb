# frozen_string_literal: true

module McpPrompts
  # Condense a post (with its comments) or a message thread into a brief summary.
  # Reads via existing tools; writes nothing.
  class SummarizeThread < McpPrompt
    prompt_name "summarize_thread"
    title "Summarize a thread"
    description "Condense a Campsite post (with its comments) or a message thread into a short summary with decisions and open questions."
    arguments [
      org_slug_arg,
      arg("post_id", description: "Public id of a post to summarize (with its comments). Provide this or thread_id."),
      arg("thread_id", description: "Public id of a message thread to summarize. Provide this or post_id."),
    ]

    def self.template(args)
      org = args["org_slug"]
      post_id = args["post_id"].presence
      thread_id = args["thread_id"].presence

      target =
        if post_id
          "the post `#{post_id}` and its comments — call `read_post` for `#{org}`"
        elsif thread_id
          "the message thread `#{thread_id}` — call `read_messages` for `#{org}`"
        else
          "a post or message thread — first ask me which one (or call `list_posts` / `list_message_threads` for `#{org}` to find it), then read it with `read_post` or `read_messages`"
        end

      user_message_result(<<~TEXT.strip)
        Summarize #{target}.

        Produce a short summary with:
        - **TL;DR** — one or two sentences on what the thread is about and where it landed.
        - **Decisions** — anything that was agreed or resolved.
        - **Open questions / next steps** — what's still unanswered or needs action, and who it's waiting on.

        Stay grounded in the actual content; quote sparingly. Don't reply, resolve, or react — this is a read-and-summarize pass.
      TEXT
    end
  end
end
