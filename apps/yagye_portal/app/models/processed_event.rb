# frozen_string_literal: true

class ProcessedEvent < ApplicationRecord
  self.primary_key = [ :event_id, :consumer ]

  validates :event_id, :consumer, :processed_at, presence: true

  def self.already_processed?(event_id:, consumer:)
    where(event_id: event_id, consumer: consumer).exists?
  end

  # Returns true if this is the first time processing, false if already seen.
  # Uses INSERT … ON CONFLICT DO NOTHING so concurrent workers are safe.
  def self.mark_processed!(event_id:, consumer:)
    result = insert(
      { event_id: event_id, consumer: consumer, processed_at: Time.current },
      unique_by: [ :event_id, :consumer ],
      returning: [ :event_id ]
    )
    result.rows.any?
  end
end
