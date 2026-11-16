# frozen_string_literal: true

class AiChatThread < ApplicationRecord
  belongs_to :user
  has_many   :ai_chat_messages, -> { order(created_at: :asc) }, dependent: :destroy

  CONTEXT_MERCHANT = "merchant"
  CONTEXT_OPS      = "ops"
  CONTEXTS         = [ CONTEXT_MERCHANT, CONTEXT_OPS ].freeze

  validates :context, inclusion: { in: CONTEXTS }

  scope :active,          -> { where(archived_at: nil) }
  scope :for_user,        ->(u) { where(user_id: u.id) }
  scope :recent,          -> { order(last_message_at: :desc).limit(20) }
  scope :in_context,      ->(ctx) { where(context: ctx) }

  def title_or_default
    title.presence || "New conversation"
  end

  # Build a title from the opening message without an LLM call.
  def self.title_from(text)
    text.to_s.strip.truncate(60, separator: " ")
  end

  # The last N messages shaped for the LLM messages array.
  def messages_for_llm(limit: 20)
    ai_chat_messages.order(created_at: :asc).last(limit).map do |m|
      { role: m.role, content: m.content }
    end
  end
end
