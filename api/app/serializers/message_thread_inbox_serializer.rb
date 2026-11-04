# frozen_string_literal: true

class MessageThreadInboxSerializer < ApiSerializer
  api_field :next_cursor, required: false, nullable: true
  api_association :threads, blueprint: MessageThreadSerializer, is_array: true
end
