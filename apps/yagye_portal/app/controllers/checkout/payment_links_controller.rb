# frozen_string_literal: true

module Checkout
  class PaymentLinksController < ApplicationController
    def index
      authorize :checkout, :index?
      result = core.list_payment_links(merchant_code: current_user.merchant_code)
      @links = result.success? ? result.body["data"] : []
      render Checkout::PaymentLinksIndexView.new(links: @links)
    end

    def new
      authorize :checkout, :new?
      render Checkout::PaymentLinkFormView.new
    end

    def create
      authorize :checkout, :create?
      result = core.create_payment_link(
        merchant_code: current_user.merchant_code,
        kind:          params[:kind].presence || "fixed_amount",
        currency:      params[:currency].presence || "GHS",
        description:   params[:description],
        amount:        parse_amount(params[:amount]),
        reusable:      params[:reusable] != "0",
        collect_email: params[:collect_email] == "1",
        collect_phone: params[:collect_phone] == "1",
        collect_name:  params[:collect_name] == "1"
      )

      if params[:kind].presence == "fixed_amount" && params[:amount].blank?
        return render Checkout::PaymentLinkFormView.new(errors: ["Amount is required for fixed-amount links"]),
                      status: :unprocessable_entity
      end

      if result.success?
        redirect_to payment_link_layout_path(result.body["id"]),
                    notice: "Payment link created. Configure the checkout layout below."
      else
        flash.now[:alert] = result.error_message
        render Checkout::PaymentLinkFormView.new(errors: [ result.error_message ]),
               status: :unprocessable_entity
      end
    end

    def layout
      authorize :checkout, :manage_layout?
      result = core.list_payment_links(merchant_code: current_user.merchant_code)
      @links = result.success? ? result.body["data"] : []
      @current = @links.find { |l| l["id"] == params[:id] }
      return redirect_to payment_links_path, alert: "Payment link not found." if @current.nil?

      render Checkout::CheckoutLayoutView.new(link: @current, all_links: @links)
    end

    def update_layout
      authorize :checkout, :manage_layout?
      raw = params[:layout]
      layout = raw.is_a?(String) ? JSON.parse(raw) : raw&.to_unsafe_h || {}
      result = core.update_payment_link_layout(
        params[:id],
        merchant_code: current_user.merchant_code,
        layout:        layout
      )

      if result.success?
        render json: { ok: true, checkout_url: result.body["checkout_url"] }
      else
        render json: { ok: false, error: result.error_message }, status: :unprocessable_entity
      end
    end

    private

    def parse_amount(raw)
      return nil if raw.blank?
      (raw.to_f * 100).round
    end

    def core
      @core ||= CoreApiClient.new
    end
  end
end
