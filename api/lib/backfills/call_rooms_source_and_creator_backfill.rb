# frozen_string_literal: true

module Backfills
  class CallRoomsSourceAndCreatorBackfill
    INSTANT_CALL_CREATION_THRESHOLD = 30.seconds

    def self.run(dry_run: true)
      thread_rooms = CallRoom.where(subject_type: "MessageThread", creator: nil, source: nil).joins("JOIN message_threads ON call_rooms.subject_id = message_threads.id")

      count = if dry_run
        thread_rooms.count
      else
        updates = CallRoom.sanitize_sql_array([
          "creator_id = message_threads.owner_id, source = ?",
          CallRoom.sources.fetch(:subject),
        ])
        thread_rooms.update_all(updates)
      end

      "#{dry_run ? "Would have updated" : "Updated"} #{count} Call #{"record".pluralize(count)}"
    end
  end
end
