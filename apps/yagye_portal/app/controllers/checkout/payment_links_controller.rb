# frozen_string_literal: true

module Checkout
  class PaymentLinksController < ApplicationController
    def index
      authorize :checkout, :index?
      result = core.list_payment_links(merchant_code: current_user.merchant_code)
      links  = result.success? ? result.body["data"] : []
      links  = filter_links(links)
      render Checkout::PaymentLinks::IndexView.new(
        links:         links,
        query:         params[:q],
        view:          params[:view].presence_in(%w[list grid]) || "list",
        active_filter: params[:active]
      )
    end

    def filter
      authorize :checkout, :index?
      render Checkout::PaymentLinks::FilterView.new(
        query:         params[:q],
        active_filter: params[:active],
        view:          params[:view]
      )
    end

    def show
      authorize :checkout, :index?
      result = core.get_payment_link(params[:id])
      return redirect_to payment_links_path, alert: "Payment link not found." unless result.success?

      link = result.body
      sessions_result = core.list_checkout_sessions(
        merchant_code:   current_user.merchant_code,
        payment_link_id: params[:id],
        limit:           500
      )
      sessions  = sessions_result.success? ? Array(sessions_result.body["data"]) : []
      analytics = {
        views:       sessions.size,
        completions: sessions.count { |s| s["state"] == "completed" },
        expired:     sessions.count { |s| s["state"] == "expired" }
      }

      config_res      = core.get_checkout_config(current_user.merchant_code)
      checkout_config = config_res.success? ? config_res.body : {}

      render Checkout::PaymentLinks::ShowView.new(link: link, analytics: analytics, checkout_config: checkout_config)
    end

    def display
      authorize :checkout, :index?
      result = core.get_payment_link(params[:id])
      return redirect_to payment_links_path, alert: "Payment link not found." unless result.success?
      link = result.body
      render Checkout::PaymentLinks::DisplayView.new(link: link)
    end

    def update_settings
      authorize :checkout, :create?

      allowed_methods = Array(params[:allowed_methods]).reject(&:blank?)
      if allowed_methods.empty?
        return redirect_to payment_link_path(params[:id]),
                           alert: "Select at least one accepted payment method."
      end

      attrs = {
        description:     params[:description].presence,
        allowed_methods: allowed_methods,
        collect_email:   params[:collect_email] == "1",
        collect_phone:   params[:collect_phone] == "1",
        collect_name:    params[:collect_name] == "1",
        max_uses:        params[:max_uses].present? ? params[:max_uses].to_i : nil,
        expires_at:      params[:expires_at].presence
      }.compact

      result = core.update_payment_link(
        params[:id],
        merchant_code: current_user.merchant_code,
        **attrs
      )

      if result.success?
        redirect_to payment_link_path(params[:id]), notice: "Settings saved."
      else
        redirect_to payment_link_path(params[:id]), alert: result.error_message || "Could not save settings."
      end
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
      config_res      = core.get_checkout_config(current_user.merchant_code)
      checkout_config = config_res.success? ? config_res.body : {}
      render Checkout::PaymentLinks::FormView.new(mode: Current.mode, checkout_config: checkout_config)
    end

    def create
      authorize :checkout, :create?

      kind = params[:kind].presence || "fixed_amount"

      config_res      = core.get_checkout_config(current_user.merchant_code)
      checkout_config = config_res.success? ? config_res.body : {}

      if params[:description].blank?
        return render Checkout::PaymentLinks::FormView.new(errors: [ "Description is required" ], mode: Current.mode, checkout_config: checkout_config),
                      status: :unprocessable_entity
      end

      if kind == "fixed_amount" && params[:amount].blank?
        return render Checkout::PaymentLinks::FormView.new(errors: [ "Amount is required for fixed-amount links" ], mode: Current.mode, checkout_config: checkout_config),
                      status: :unprocessable_entity
      end

      allowed_methods = Array(params[:allowed_methods]).reject(&:blank?)
      if allowed_methods.empty?
        return render Checkout::PaymentLinks::FormView.new(errors: [ "Select at least one accepted payment method" ], mode: Current.mode, checkout_config: checkout_config),
                      status: :unprocessable_entity
      end

      reusable = params[:reusable] == "1"

      amount = kind == "customer_specified" ? nil : parse_amount(params[:amount])

      result = core.create_payment_link(
        merchant_code:              current_user.merchant_code,
        kind:                       kind,
        currency:                   params[:currency].presence || "GHS",
        description:                params[:description],
        amount:                     amount,
        discount_amount:            parse_amount(params[:discount_amount]),
        allowed_methods:            allowed_methods,
        collect_email:              params[:collect_email] == "1",
        collect_phone:              params[:collect_phone] == "1",
        collect_name:               params[:collect_name] == "1",
        reusable:                   reusable,
        max_uses:                   (reusable && params[:max_uses].present?) ? params[:max_uses].to_i : nil,
        expires_at:                 params[:expires_at].presence,
        escrow_enabled:             params[:escrow_enabled] == "1",
        escrow_auto_release_days:   params[:escrow_auto_release_days].present? ? params[:escrow_auto_release_days].to_i : 7,
        escrow_dispute_window_hours: params[:escrow_dispute_window_hours].present? ? params[:escrow_dispute_window_hours].to_i : 48
      )

      if result.success?
        link_id = result.body["id"]
        save_appearance_after_create(link_id)
        redirect_to payment_link_path(link_id), notice: "Payment link created."
      else
        render Checkout::PaymentLinks::FormView.new(errors: [ result.error_message ], mode: Current.mode, checkout_config: checkout_config),
               status: :unprocessable_entity
      end
    end

    def layout
      redirect_to payment_link_path(params[:id])
    end

    def update_layout
      authorize :checkout, :manage_layout?
      raw    = params[:layout]
      layout = raw.is_a?(String) ? JSON.parse(raw) : raw&.to_unsafe_h || {}
      mode   = layout["mode"].presence || "live"

      # 1. Merchant-level branding → merchant_checkout_configs
      branding_attrs = {}
      branding_attrs[:brand_colour] = layout["brand_color"] if layout["brand_color"].present?
      branding_attrs[:display_name] = layout["business_name"] if layout["business_name"].present?
      core.update_checkout_config(current_user.merchant_code, **branding_attrs) if branding_attrs.any?

      # 2. Template theme (font, method visual config) → checkout_template (auto-publishes)
      template_attrs = { mode: mode }
      template_attrs[:font_family] = layout["font_family"] if layout["font_family"].present?
      template_attrs[:methods]     = layout["methods"]     if layout["methods"].present?
      core.update_checkout_template(current_user.merchant_code, **template_attrs) if template_attrs.size > 1

      # 3. Per-link display fields → payment_link.checkout_layout JSONB
      #    Logo is server-injected from PortalMerchantBranding (never from user input).
      branding = current_user.merchant_user? ? PortalMerchantBranding.find_or_initialize_for(current_user.merchant_code) : nil
      per_link = layout.slice("headline", "cta_text", "terms", "methods")
      if branding&.logo&.attached?
        per_link = per_link.merge("logo_url" => branding.logo_url)
      end

      result = core.update_payment_link_layout(
        params[:id],
        merchant_code: current_user.merchant_code,
        layout:        per_link
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

    def save_appearance_after_create(link_id)
      cc = params[:checkout_config] || {}
      cl = params[:checkout_layout]  || {}

      # Merchant-level branding
      branding = {}
      branding[:brand_colour] = cc[:brand_colour].presence if cc[:brand_colour].present?
      branding[:display_name] = cc[:display_name].presence if cc[:display_name].present?
      core.update_checkout_config(current_user.merchant_code, **branding) if branding.any?

      # Template font
      font = cl[:font_family].presence
      core.update_checkout_template(current_user.merchant_code, mode: Current.mode, font_family: font) if font

      # Per-link layout (headline, cta_text, terms, logo_url)
      per_link = {}
      per_link["headline"]  = cl[:headline].presence  if cl[:headline].present?
      per_link["cta_text"]  = cl[:cta_text].presence  if cl[:cta_text].present?
      if cl[:terms_enabled] == "1"
        per_link["terms"] = {
          "enabled" => true,
          "label"   => cl[:terms_label].presence || "I agree to the Terms & Conditions",
          "url"     => cl[:terms_url].to_s
        }
      end
      link_branding = current_user.merchant_user? ? PortalMerchantBranding.find_or_initialize_for(current_user.merchant_code) : nil
      per_link["logo_url"] = link_branding.logo_url if link_branding&.logo&.attached?
      core.update_payment_link_layout(link_id, merchant_code: current_user.merchant_code, layout: per_link) if per_link.any?
    rescue StandardError
      # Non-fatal — link is created, appearance can be set on the show page
    end

    def core
      @core ||= CoreApiClient.new
    end
  end
end
