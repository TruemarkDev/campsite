# frozen_string_literal: true

class ScheduledNotification < ApplicationRecord
  include PublicIdGenerator

  WEEKLY_DIGEST = "weekly_digest"
  DAILY_DIGEST = "daily_digest"
  NAMES = [DAILY_DIGEST, WEEKLY_DIGEST].freeze

  belongs_to :schedulable, polymorphic: true

  validates :delivery_time, :time_zone, presence: true
  validates :name, inclusion: { in: NAMES, list: NAMES }

  validate :timezone_exists

  enum :delivery_day,
    {
      sunday: 0,
      monday: 1,
      tuesday: 2,
      wednesday: 3,
      thursday: 4,
      friday: 5,
      saturday: 6,
    }

  scope :post_digests, -> { where(name: [DAILY_DIGEST, WEEKLY_DIGEST]) }

  scope :schedulable_in, ->(time) do
    now = Time.current
    finish = time.from_now
    offset = Arel.sql("COALESCE(scheduled_notifications.delivery_offset, 0)")

    if connection.adapter_name == "PostgreSQL"
      min_dt = "((CAST(:now AS timestamp) AT TIME ZONE 'UTC') AT TIME ZONE scheduled_notifications.time_zone) - (#{offset} * INTERVAL '1 second')"
      max_dt = "((CAST(:end AS timestamp) AT TIME ZONE 'UTC') AT TIME ZONE scheduled_notifications.time_zone) - (#{offset} * INTERVAL '1 second')"
      local_date = "CAST(#{min_dt} AS DATE)"
      local_time_min = "CAST(#{min_dt} AS TIME)"
      local_time_max = "CAST(#{max_dt} AS TIME)"
      weekday_min = "EXTRACT(DOW FROM #{min_dt})"
      weekday_max = "EXTRACT(DOW FROM #{max_dt})"
      same_day = "#{local_date} = CAST(#{max_dt} AS DATE)"
      next_day = "CAST(#{max_dt} AS DATE) - #{local_date} = 1"
    else
      min_dt = "CONVERT_TZ(:now, '+00:00', scheduled_notifications.time_zone) - INTERVAL COALESCE(scheduled_notifications.delivery_offset, 0) SECOND"
      max_dt = "CONVERT_TZ(:end, '+00:00', scheduled_notifications.time_zone) - INTERVAL COALESCE(scheduled_notifications.delivery_offset, 0) SECOND"
      local_date = "DATE(#{min_dt})"
      local_time_min = "TIME(#{min_dt})"
      local_time_max = "TIME(#{max_dt})"
      weekday_min = "DAYOFWEEK(#{min_dt}) - 1"
      weekday_max = "DAYOFWEEK(#{max_dt}) - 1"
      same_day = "DATE(#{min_dt}) = DATE(#{max_dt})"
      next_day = "DATEDIFF(DATE(#{max_dt}), DATE(#{min_dt})) = 1"
    end

    delivery_time = "scheduled_notifications.delivery_time"
    daily_window = <<~SQL.squish
      (#{same_day})
      AND (scheduled_notifications.delivery_day IS NULL OR scheduled_notifications.delivery_day = #{weekday_min})
      AND #{delivery_time} BETWEEN #{local_time_min} AND #{local_time_max}
    SQL
    crossing_window = <<~SQL.squish
      (#{next_day})
      AND (
        ((scheduled_notifications.delivery_day IS NULL OR scheduled_notifications.delivery_day = #{weekday_min}) AND #{delivery_time} >= #{local_time_min})
        OR ((scheduled_notifications.delivery_day IS NULL OR scheduled_notifications.delivery_day = #{weekday_max}) AND #{delivery_time} <= #{local_time_max})
      )
    SQL

    where("(#{daily_window}) OR (#{crossing_window})", { now: now, end: finish })
  end

  def weekly_digest?
    name == WEEKLY_DIGEST
  end

  def daily_digest?
    name == DAILY_DIGEST
  end

  def display_name
    name.humanize.capitalize
  end

  def api_type_name
    "ScheduledNotification"
  end

  def formatted_delivery_time
    # formats delivery time to eg. 9:00 am
    delivery_time.strftime("%l:%M %P").strip
  end

  private

  def timezone_exists
    return unless time_zone
    return if TZInfo::Timezone.all_identifiers.include?(time_zone)

    errors.add(:time_zone, "does not exist")
  end
end
