# frozen_string_literal: true

module Eventable
  extend ActiveSupport::Concern

  included do
    has_many :events, as: :subject, dependent: :destroy_async
    has_many :notifications, through: :events
    after_create_commit :instrument_created_event
    after_update_commit :instrument_updated_event, unless: -> { respond_to?(:discarded?) && discarded? }
    # Latch the discard at save time: a later save in the same transaction (e.g.
    # Post#remove_from_version_tree's `update!`) overwrites the discarded_at dirty
    # state, so the commit callback below can't reliably read it via
    # `discarded_at_previously_changed?`. after_save sees each save's own changes.
    after_save :flag_destroyed_event, if: -> { respond_to?(:discarded?) && discarded? && saved_change_to_attribute?(self.class.discard_column) }
    # Must use after_update_commit instead of after_discard to ensure that
    # transaction is committed and Event is available to ProcessEventJob
    # https://github.com/jhawthorn/discard/issues/73#issue-576101350
    after_update_commit :instrument_destroyed_event, if: -> { @destroyed_event_pending }
    delegate :display_name, to: :event_actor, prefix: true, allow_nil: true
    attr_accessor :skip_notifications
    alias_method :skip_notifications?, :skip_notifications
  end

  def instrument_published_event
    event = events.published_action.create!(**event_attributes)
    ProcessEventJob.perform_async(event.id)
  end

  private

  def instrument_created_event
    event = events.created_action.create!(**event_attributes)
    ProcessEventJob.perform_async(event.id)
  end

  def instrument_updated_event
    event = events.updated_action.create!(**event_attributes)
    ProcessEventJob.perform_async(event.id)
  end

  def flag_destroyed_event
    @destroyed_event_pending = true
  end

  def instrument_destroyed_event
    @destroyed_event_pending = false
    event = events.destroyed_action.create!(**event_attributes)
    ProcessEventJob.perform_async(event.id)
  end

  def event_attributes
    {
      actor: event_actor,
      organization: event_organization,
      metadata: {
        subject_previous_changes: previous_changes,
        actor_display_name: event_actor_display_name,
      },
      skip_notifications: skip_notifications.presence || false,
    }
  end
end
