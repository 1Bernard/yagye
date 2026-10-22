# frozen_string_literal: true

# Purges processed_events rows older than 30 days.
# Scheduled to run nightly — keeps the table from growing unbounded.
# Safe to re-run: any row deleted was too old to deduplicate anyway.
class ProcessedEventSweepJob < ApplicationJob
  queue_as :default

  RETENTION = 30.days

  def perform
    cutoff  = RETENTION.ago
    deleted = ProcessedEvent.where("processed_at < ?", cutoff).delete_all
    Rails.logger.info("[ProcessedEventSweepJob] deleted=#{deleted} cutoff=#{cutoff.iso8601}")
  end
end
