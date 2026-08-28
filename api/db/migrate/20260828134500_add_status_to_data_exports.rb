# frozen_string_literal: true

class AddStatusToDataExports < ActiveRecord::Migration[8.1]
  def up
    add_column(:data_exports, :status, :integer, null: false, default: 0) unless column_exists?(:data_exports, :status)

    safety_assured do
      execute <<~SQL.squish
        UPDATE data_exports
        SET status = 2
        WHERE completed_at IS NOT NULL
      SQL

      execute <<~SQL.squish
        UPDATE data_exports
        INNER JOIN (
          SELECT DISTINCT data_export_id
          FROM data_export_resources
          WHERE status = 2
        ) failed_resources ON failed_resources.data_export_id = data_exports.id
        SET data_exports.status = 3
        WHERE data_exports.completed_at IS NULL
      SQL
    end
  end

  def down
    remove_column(:data_exports, :status)
  end
end
