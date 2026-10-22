# frozen_string_literal: true

# Recomputes portal_daily_metrics for today and yesterday.
# Intended to run hourly via a scheduler (e.g. Solid Queue cron or similar).
# Recompute is idempotent — any execution produces the correct aggregate.
class PortalDailyMetricsRecomputeJob < ApplicationJob
  queue_as :default

  def perform(date: Date.current)
    days = [ date, date - 1 ].uniq

    days.each do |day|
      PortalDailyMetric.recompute_all_for_day!(day)
      Rails.logger.info("[PortalDailyMetricsRecomputeJob] recomputed day=#{day}")
    end
  end
end
