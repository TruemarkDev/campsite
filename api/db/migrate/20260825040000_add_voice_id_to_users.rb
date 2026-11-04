# frozen_string_literal: true

class AddVoiceIdToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column(:users, :voice_id, :string)
  end
end
