# frozen_string_literal: true

class AiChatMessage < ApplicationRecord
  self.record_timestamps = false  # append-only; no updated_at column

  belongs_to :ai_chat_thread

  validates :role,    inclusion: { in: %w[user assistant] }
  validates :content, presence: true

  before_create { self.created_at ||= Time.current }
end
