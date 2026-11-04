# frozen_string_literal: true

class ChannelAgentSummarySerializer < ApiSerializer
  api_field :id do |entry|
    entry.fetch(:application).public_id
  end
  api_field :name do |entry|
    entry.fetch(:application).name
  end
  api_field :avatar_url do |entry|
    entry.fetch(:application).avatar_url
  end
  api_field :avatar_urls, blueprint: AvatarUrlsSerializer do |entry|
    entry.fetch(:application).avatar_urls
  end
  api_field :status, enum: ["Attached"] do
    "Attached"
  end
  api_field :roles, is_array: true, enum: ["Agent", "Beads publisher"]
end
