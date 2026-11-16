# frozen_string_literal: true

module PricingPlans
  class ShowView < ApplicationComponent
    include UI::Theme

    METHOD_OPTIONS = [
      [ "— All methods (catch-all)", "" ],
      [ "Mobile Money",  "mobile_money" ],
      [ "Card",          "card" ],
      [ "Bank Transfer", "bank_transfer" ]
    ].freeze

    FEE_KIND_OPTIONS = [
      [ "PSP margin (Model A — Yagye is PSP)",                    "psp_margin"       ],
      [ "Orchestration fee (Model B — merchant's own PSP)",       "orchestration_fee" ]
    ].freeze

    PROVIDER_OPTIONS = {
      "mobile_money" => [
        [ "MTN MoMo (native rail)",    "mtn_momo_gh" ],
        [ "Telecel Cash (native rail)", "telecel_cash_gh" ],
        [ "AirtelTigo (native rail)",  "airteltigo_money_gh" ],
        [ "Flutterwave (MoMo)",        "flutterwave" ],
        [ "Paystack (MoMo)",           "paystack" ]
      ],
      "card" => [
        [ "Flutterwave (card)",        "flutterwave" ],
        [ "Paystack (card)",           "paystack" ],
        [ "Stripe (USD card)",         "stripe" ]
      ]
    }.freeze

    PROVIDER_LABEL_MAP = {
      "mtn_momo_gh"        => "MTN MoMo",
      "telecel_cash_gh"    => "Telecel Cash",
      "airteltigo_money_gh" => "AirtelTigo Money",
      "flutterwave"        => "Flutterwave",
      "paystack"           => "Paystack",
      "stripe"             => "Stripe"
    }.freeze

    def initialize(plan:)
      @plan = plan
    end

    def view_template
      cur     = @plan["currency"] || "GHS"
      mode    = @plan["fee_mode"] == "invoiced" ? "Invoiced monthly" : "Deducted from settlement"
      monthly = @plan["monthly_fee"].to_i
      status  = @plan["status"] || "draft"
      eff     = begin
        fmt_date(Date.parse(@plan["effective_from"].to_s)) if @plan["effective_from"]
      rescue ArgumentError, TypeError
        "—"
      end

      render Layout::Shell.new(
        active_nav:  :pricing_plans,
        title:       @plan["name"] || "Pricing Plan",
        breadcrumbs: [
          { label: "Pricing Plans", href: pricing_plans_path },
          { label: @plan["name"] || "Plan" }
        ]
      ) do
        render UI::PageHeader.new(
          title:    @plan["name"] || "Pricing Plan",
          subtitle: "v#{@plan["version"]} · #{mode}"
        ) do
          div(class: "flex items-center gap-2") do
            render UI::StatusBadge.new(status: status)
            if status == "draft" && can?(:update?, :pricing_plans)
              form(action: activate_pricing_plan_path(@plan["id"]), method: "post",
                   data: { turbo_confirm: "Activate this plan? A different ops member must approve to enforce maker-checker." }) do
                input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                render UI::Button.new(variant: :primary, type: "submit") { plain "Activate plan" }
              end
            end
          end
        end

        render UI::Grid.new(columns: :sidebar) do
          # ── Left: rate card + add rule form ──────────────────────────────────
          div(class: "flex flex-col gap-5") do
            render UI::Card.new do |c|
              c.header("Rate card")
              c.body(padding: false) do
                render UI::PricingRateCard.new(plan: @plan)
              end
            end

            add_rule_form if can?(:update?, :pricing_plans)
          end

          # ── Right: plan metadata + rules list ────────────────────────────────
          div(class: "flex flex-col gap-5") do
            render UI::Card.new do |c|
              c.header("Plan details", icon: :tag)
              c.body(padding: false) do
                render UI::DetailList.new do |list|
                  list.row("Version",      "v#{@plan["version"]}")
                  list.row("Status") { render UI::StatusBadge.new(status: status) }
                  list.row("Currency",     cur)
                  list.row("Fee mode",     mode)
                  list.row("Monthly fee",  monthly.positive? ? format_money(monthly, currency: cur) : "None")
                  list.row("Active from",  eff || "—")
                  list.row("Created by",   @plan["created_by"] || "—")
                  list.row("Activated by", @plan["activated_by"] || "—")
                end
              end
            end

            rules_list_card
          end
        end
      end
    end

    private

    def add_rule_form
      cur = @plan["currency"] || "GHS"

      render UI::Card.new do |c|
        c.header("Add rule", icon: :plus)
        c.body do
          form(action: pricing_plan_rules_path(@plan["id"]), method: "post") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

            div(class: "flex flex-col gap-4") do
              div do
                label(class: "block #{TYPE_MICRO} text-gray-500 font-medium mb-1.5") { plain "Fee kind" }
                select(name: "fee_kind", class: input_cls) do
                  FEE_KIND_OPTIONS.each { |(lbl, val)| option(value: val) { plain lbl } }
                end
                p(class: "#{TYPE_MICRO} text-gray-400 mt-1") do
                  plain "PSP margin = Yagye is the PSP. Orchestration fee = merchant uses their own PSP (Stripe/Paystack/Flutterwave), Yagye routes."
                end
              end

              div do
                label(class: "block #{TYPE_MICRO} text-gray-500 font-medium mb-1.5") { plain "Payment method" }
                select(name: "method", class: input_cls) do
                  METHOD_OPTIONS.each { |(lbl, val)| option(value: val) { plain lbl } }
                end
              end

              div do
                label(class: "block #{TYPE_MICRO} text-gray-500 font-medium mb-1.5") { plain "Provider (optional — leave blank for catch-all)" }
                select(name: "provider_code", class: input_cls) do
                  option(value: "") { plain "— All providers (catch-all)" }
                  PROVIDER_OPTIONS.each do |_m, opts|
                    opts.each { |(lbl, val)| option(value: val) { plain lbl } }
                  end
                end
                p(class: "#{TYPE_MICRO} text-gray-400 mt-1") do
                  plain "PSP-specific rules beat catch-all rules of the same method (higher specificity)."
                end
              end

              div(class: "grid grid-cols-2 gap-3") do
                rate_field("Rate (%)", "percentage_pct", "1.75")
                rate_field("Fixed fee (#{cur})", "fixed_amount", "0.50")
              end
              div(class: "grid grid-cols-2 gap-3") do
                rate_field("Min charge (#{cur})", "minimum_fee", "0.50")
                rate_field("Cap (#{cur})", "maximum_fee", "50.00")
              end

              div(class: "flex justify-end pt-1") do
                render UI::Button.new(variant: :primary, type: "submit") { plain "Add rule" }
              end
            end
          end
        end
      end
    end

    def rules_list_card
      rules = @plan["rules"] || []
      return if rules.empty?

      render UI::Card.new do |c|
        c.header("Rules (#{rules.size})", icon: :list)
        c.body(padding: false) do
          div(class: "divide-y divide-gray-50") do
            rules.each { |r| rule_row(r) }
          end
        end
      end
    end

    def rule_row(r)
      cur          = @plan["currency"] || "GHS"
      method_label = r["method"] ? r["method"].tr("_", " ").split.map(&:capitalize).join(" ") : "All methods"
      prov_label   = r["provider_code"]&.then { |c| PROVIDER_LABEL_MAP[c.upcase] || c } || "All providers"
      pct          = r["percentage_bps"].to_i
      pct_label    = pct.positive? ? "#{sprintf('%.4f', pct / 100.0).sub(/0+$/, '').sub(/\.$/, '.0')}%" : "—"
      rule_ref     = r["id"].to_s.first(8)

      fee_kind    = r["fee_kind"] || "psp_margin"
      kind_label  = fee_kind == "orchestration_fee" ? "Orchestration" : "PSP margin"
      kind_css    = fee_kind == "orchestration_fee" ? STATUS_INFO : STATUS_NEUTRAL

      div(class: "flex items-center gap-3 px-5 py-3.5") do
        div(class: "flex-1 min-w-0") do
          div(class: "flex items-center gap-2 flex-wrap") do
            p(class: TYPE_BODY_MD) { plain "#{method_label} · #{prov_label}" }
            span(class: "#{BADGE_XS} #{kind_css}") { plain kind_label }
          end
          p(class: TYPE_CAPTION) do
            parts = [ pct_label ]
            parts << "#{format_money(r["fixed_amount"].to_i, currency: cur)} fixed" if r["fixed_amount"].to_i > 0
            plain parts.join(" + ")
          end
        end
        span(class: "#{BADGE} #{STATUS_NEUTRAL} #{TYPE_MONO} shrink-0") { plain rule_ref }
      end
    end

    def rate_field(label_text, name, placeholder)
      div do
        label(class: "block #{TYPE_MICRO} text-gray-500 font-medium mb-1.5") { plain label_text }
        input(type: "text", name: name, placeholder: placeholder, class: input_cls)
      end
    end

    def input_cls
      "w-full border border-gray-200 rounded-xl px-3.5 py-2.5 text-[13px] text-gray-800 " \
        "bg-white focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400"
    end
  end
end
