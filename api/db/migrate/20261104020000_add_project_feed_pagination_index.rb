# frozen_string_literal: true

class AddProjectFeedPaginationIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :posts, [:project_id, :published_at, :id],
      order: { published_at: :desc, id: :desc },
      where: "discarded_at IS NULL AND stale = false AND workflow_state = 'published'",
      name: "index_posts_on_active_project_pagination", algorithm: :concurrently
  end
end
