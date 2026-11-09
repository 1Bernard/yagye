# frozen_string_literal: true

module Developers
  class SandboxRunsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_merchant!

    def create
      skip_authorization
      merchant_code = current_user.merchant_code
      session_id    = "cks_#{SecureRandom.hex(10)}"

      render json: {
        id:              session_id,
        object:          "checkout_session",
        status:          "open",
        mode:            "test",
        currency:        "GHS",
        subtotal_amount: 25_000,
        total_amount:    25_000,
        description:     "Order #001",
        checkout_url:    "https://pay.yagye.com/s/#{session_id}",
        success_url:     "https://yourstore.com/success?session_id={CHECKOUT_SESSION_ID}",
        cancel_url:      "https://yourstore.com/cart",
        collect_email:   true,
        merchant_code:   merchant_code,
        line_items: [
          {
            kind:         "item",
            description:  "Blue Sneakers – Size 42",
            quantity:     1,
            unit_amount:  25_000,
            total_amount: 25_000
          }
        ],
        metadata:    { order_id: "ord_789" },
        created_at:  Time.current.iso8601,
        expires_at:  30.minutes.from_now.iso8601
      }
    rescue StandardError => e
      Rails.logger.error("[Developers::SandboxRunsController] #{e.class}: #{e.message}")
      render json: { error: "Failed to generate sandbox response." }, status: :internal_server_error
    end

    private

    def require_merchant!
      return if current_user&.merchant_user?
      render json: { error: "Not authorized" }, status: :forbidden
    end
  end
end
