# frozen_string_literal: true

# Delivers a transactional SMS via Brevo in the background.
# Discards non-retryable API errors (bad number, blocked sender)
# so a single bad recipient never stalls the queue.
class SmsNotifierJob < ApplicationJob
  queue_as :mailers

  # 4xx responses from Brevo are non-retryable — discard silently after logging.
  discard_on(StandardError) do |_job, error|
    Rails.logger.error("[SmsNotifierJob] Discarding after error: #{error.class} #{error.message}")
  end

  def perform(to:, content:, tag: nil)
    result = Brevo::SmsClient.send_sms(to: to, content: content, tag: tag)
    raise "Brevo SMS failed: #{result.error}" unless result.success
  end
end
