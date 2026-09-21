# frozen_string_literal: true

module Checkout
  class PaymentLinksController < ApplicationController
    def index
      authorize :checkout, :index?
      result = core.list_payment_links(merchant_code: current_user.merchant_code)
      links  = result.success? ? result.body["data"] : []
      links  = filter_links(links)
      render Checkout::PaymentLinksIndexView.new(
        links:         links,
        query:         params[:q],
        view:          params[:view].presence_in(%w[list grid]) || "list",
        active_filter: params[:active]
      )
    end

    def filter
      authorize :checkout, :index?
      render Checkout::PaymentLinksFilterView.new(
        query:         params[:q],
        active_filter: params[:active],
        view:          params[:view]
      )
    end

    def show
      authorize :checkout, :index?
      result = core.get_payment_link(params[:id])
      return redirect_to payment_links_path, alert: "Payment link not found." unless result.success?
      render Checkout::PaymentLinks::ShowView.new(link: result.body)
    end

    def deactivate
      authorize :checkout, :create?
      result = core.deactivate_payment_link(params[:id])
      if result.success?
        redirect_to payment_link_path(params[:id]), notice: "Payment link deactivated."
      else
        redirect_to payment_link_path(params[:id]), alert: result.error_message
      end
    end

    def new
      authorize :checkout, :new?
      render Checkout::PaymentLinkFormView.new(mode: Current.mode)
    end

    def create
      authorize :checkout, :create?

      kind = params[:kind].presence || "fixed_amount"
      if kind == "fixed_amount" && params[:amount].blank?
        return render Checkout::PaymentLinkFormView.new(errors: ["Amount is required for fixed-amount links"], mode: Current.mode),
                      status: :unprocessable_entity
      end

      allowed_methods = Array(params[:allowed_methods]).reject(&:blank?)
      if allowed_methods.empty?
        return render Checkout::PaymentLinkFormView.new(errors: ["Select at least one accepted payment method"], mode: Current.mode),
                      status: :unprocessable_entity
      end

      reusable = params[:reusable] == "1"

      result = core.create_payment_link(
        merchant_code:   current_user.merchant_code,
        kind:            kind,
        currency:        params[:currency].presence || "GHS",
        description:     params[:description],
        amount:          parse_amount(params[:amount]),
        allowed_methods: allowed_methods,
        collect_email:   params[:collect_email] == "1",
        collect_phone:   params[:collect_phone] == "1",
        collect_name:    params[:collect_name] == "1",
        reusable:        reusable,
        max_uses:        (reusable && params[:max_uses].present?) ? params[:max_uses].to_i : nil,
        expires_at:      params[:expires_at].presence
      )

      if result.success?
        redirect_to payment_link_layout_path(result.body["id"]),
                    notice: "Payment link created. Configure the checkout layout below."
      else
        render Checkout::PaymentLinkFormView.new(errors: [ result.error_message ], mode: Current.mode),
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

    def filter_links(links)
      links = links.reject { |l| l["kind"] == "invoice" }
      links = links.select { |l| l["description"].to_s.downcase.include?(params[:q].downcase) ||
                                 l["url_slug"].to_s.downcase.include?(params[:q].downcase) } if params[:q].present?
      if params[:active].present?
        active = params[:active] == "true"
        links = links.select { |l| l["active"] == active }
      end
      links
    end

    def parse_amount(raw)
      return nil if raw.blank?
      (raw.to_f * 100).round
    end

    def core
      @core ||= CoreApiClient.new
    end
  end
end
