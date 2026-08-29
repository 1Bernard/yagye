# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    authorize :dashboard, :index?
    scope = payment_scope

    summary = Payments::VolumeSummaryQuery.new(scope).call

    @volume_cents      = summary[:volume_cents]
    @prev_volume_cents = summary[:prev_volume_cents]
    @tx_count          = summary[:tx_count]
    @prev_tx_count     = summary[:prev_tx_count]
    @success_count     = summary[:success_count]
    @pending_count     = summary[:pending_count]
    @failed_count      = summary[:failed_count]
    @success_rate      = summary[:success_rate]
    @chart_dates       = summary[:chart_dates]
    @chart_values      = summary[:chart_values]
    @provider_data     = summary[:provider_data]

    @disputes_count    = 0
    @kyb_pending_count = current_user.internal_staff? ? kyb_pending_count : nil
    @recent_payments   = scope.recent.limit(8)
  end

  private

  def payment_scope
    current_user.internal_staff? ? Payment.all : Payment.for_merchant(current_user.merchant_code)
  end

  def kyb_pending_count
    PortalMerchantApplication.pending_review.count
  rescue StandardError
    0
  end
end
