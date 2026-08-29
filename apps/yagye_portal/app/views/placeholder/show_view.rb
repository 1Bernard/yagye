# frozen_string_literal: true

module Placeholder
  class ShowView < ApplicationComponent
    include UI::Theme

    SECTIONS = {
      "payments"    => {
        icon: :credit_card,    color: "#3D47F5", tint: "rgba(61,71,245,0.08)",
        nav:  :payments,       phase: "P11",
        subtitle: "Accept and manage payments from customers across mobile money, card, and bank transfer channels.",
        features: [
          { icon: :layers,      label: "Full payment list",       desc: "Search, filter, and export all transactions with real-time status." },
          { icon: :filter,      label: "Smart filters",           desc: "Filter by provider, method, status, date range, and amount." },
          { icon: :chart,       label: "Analytics overlay",       desc: "Volume trends, success rates, and provider performance inline." },
          { icon: :download,    label: "CSV / PDF export",        desc: "Export any filtered view for reconciliation or reporting." }
        ]
      },
      "disputes"    => {
        icon: :flag,           color: "#dc2626", tint: "rgba(220,38,38,0.08)",
        nav:  :disputes,       phase: "P12",
        subtitle: "Manage chargebacks and payment disputes with evidence submission, SLA tracking, and resolution workflow.",
        features: [
          { icon: :flag,        label: "Dispute queue",           desc: "All open disputes with SLA countdown and assigned owner." },
          { icon: :file,        label: "Evidence upload",         desc: "Upload PDFs, screenshots, and transaction logs per dispute." },
          { icon: :refresh,     label: "Resolution workflow",     desc: "Accept, contest, or escalate with full audit trail." },
          { icon: :bell,        label: "SLA alerts",              desc: "Automatic alerts before network deadlines are breached." }
        ]
      },
      "merchants"   => {
        icon: :building,       color: "#0d9488", tint: "rgba(13,148,136,0.08)",
        nav:  :merchants,      phase: "P13",
        subtitle: "Onboard and manage merchant accounts, KYB status, limits, and integration credentials.",
        features: [
          { icon: :building,    label: "Merchant directory",      desc: "Full list of live, pending, and suspended merchant accounts." },
          { icon: :shield,      label: "KYB review queue",        desc: "Documents, UBO declarations, and risk scoring per merchant." },
          { icon: :key,         label: "Credential management",   desc: "Generate and rotate API keys and webhook secrets." },
          { icon: :chart,       label: "Per-merchant analytics",  desc: "Volume, dispute rate, and fee income per account." }
        ]
      },
      "kyb reviews" => {
        icon: :shield,         color: "#6d28d9", tint: "rgba(109,40,217,0.08)",
        nav:  :kyb_reviews,    phase: "P13",
        subtitle: "Review merchant KYB applications, verify documents, set risk tiers, and trigger compliance screening.",
        features: [
          { icon: :file,        label: "Application queue",       desc: "Pending and in-review applications sorted by submission date." },
          { icon: :shield,      label: "Document verification",   desc: "View uploaded certificates, IDs, and proof of address." },
          { icon: :alert_circle, label: "AML / PEP screening",    desc: "Automated sanctions and PEP screening results per merchant." },
          { icon: :check,       label: "Approve / Reject",        desc: "Tier assignment, notes, and approval with full audit log." }
        ]
      },
      "api keys"    => {
        icon: :key,            color: "#d97706", tint: "rgba(217,119,6,0.08)",
        nav:  :api_keys,       phase: "P13",
        subtitle: "Create and manage API keys for your integration. Rotate secrets, set expiry, and monitor usage per key.",
        features: [
          { icon: :plus,        label: "Generate keys",           desc: "Create sandbox and live keys with descriptive labels." },
          { icon: :refresh,     label: "Rotate & revoke",         desc: "Immediately rotate a key or revoke it with zero downtime." },
          { icon: :chart,       label: "Usage analytics",         desc: "Requests per key, error rates, and latency percentiles." },
          { icon: :bell,        label: "Expiry alerts",           desc: "Alerts before keys expire to prevent production outages." }
        ]
      },
      "settings"    => {
        icon: :settings,       color: "#374151", tint: "rgba(55,65,81,0.08)",
        nav:  :settings,       phase: "P13",
        subtitle: "Configure your portal: profile, team members, webhook endpoints, notification preferences, and allowlists.",
        features: [
          { icon: :user,        label: "Profile & security",      desc: "Name, email, password, TOTP, and session management." },
          { icon: :users,       label: "Team members",            desc: "Invite staff, assign roles, and manage permissions." },
          { icon: :globe,       label: "Webhook endpoints",       desc: "Register, test, and monitor webhook delivery per event type." },
          { icon: :bell,        label: "Notifications",           desc: "Configure email and in-app alerts for key events." }
        ]
      },
      "help"        => {
        icon: :headset,        color: "#0d9488", tint: "rgba(13,148,136,0.08)",
        nav:  nil,             phase: "P13",
        subtitle: "Access documentation, integration guides, status page, and open a support ticket with the Yagye team.",
        features: [
          { icon: :file,        label: "Documentation",           desc: "API reference, webhook events, and integration guides." },
          { icon: :headset,     label: "Support tickets",         desc: "Open, track, and respond to support requests." },
          { icon: :globe,       label: "System status",           desc: "Live uptime and incident history for all Yagye services." },
          { icon: :info_circle, label: "Changelog",               desc: "Release notes for every portal and API update." }
        ]
      }
    }.freeze

    def initialize(section:)
      @section = section.to_s.downcase
      @meta    = SECTIONS.fetch(@section, default_meta)
    end

    def view_template
      render Layout::Shell.new(
        active_nav: @meta[:nav],
        title:      @section.split.map(&:capitalize).join(" "),
        breadcrumbs: [ { label: @section.split.map(&:capitalize).join(" ") } ]
      ) do
        hero_banner
        feature_grid
      end
    end

    private

    def hero_banner
      div(style: "background:#fff;border:1px solid #f3f4f6;border-radius:16px;padding:48px 40px 44px;" \
                 "display:flex;flex-direction:column;align-items:center;text-align:center;" \
                 "margin-bottom:20px;position:relative;overflow:hidden") do
        # Decorative radial glow
        div(style: "position:absolute;top:-60px;left:50%;transform:translateX(-50%);" \
                   "width:360px;height:240px;border-radius:50%;" \
                   "background:radial-gradient(ellipse at center, #{@meta[:tint]} 0%, transparent 70%);" \
                   "pointer-events:none")

        # Phase badge
        span(style: "display:inline-flex;align-items:center;gap:5px;padding:4px 12px;" \
                    "border-radius:20px;background:#{@meta[:tint]};font-size:11px;font-weight:600;" \
                    "color:#{@meta[:color]};letter-spacing:0.06em;margin-bottom:20px;position:relative") do
          span(style: "width:5px;height:5px;border-radius:50%;background:#{@meta[:color]}")
          plain "#{@meta[:phase]} · Coming Soon"
        end

        # Icon
        div(style: "width:56px;height:56px;border-radius:16px;background:#{@meta[:tint]};" \
                   "display:flex;align-items:center;justify-content:center;margin-bottom:18px;position:relative") do
          span(style: "color:#{@meta[:color]};display:flex;width:26px;height:26px") do
            render UI::Icon.new(@meta[:icon], class: "w-full h-full")
          end
        end

        h2(style: "font-size:22px;font-weight:700;color:#111827;letter-spacing:-0.02em;margin-bottom:10px") do
          plain @section.split.map(&:capitalize).join(" ")
        end

        p(style: "font-size:14px;color:#6b7280;max-width:460px;line-height:1.65") do
          plain @meta[:subtitle]
        end
      end
    end

    def feature_grid
      div(style: "display:grid;grid-template-columns:repeat(2,1fr);gap:12px") do
        @meta[:features].each { |f| feature_card(f) }
      end
    end

    def feature_card(feat)
      div(style: "background:#fff;border:1px solid #f3f4f6;border-radius:14px;padding:20px 22px;" \
                 "display:flex;align-items:flex-start;gap:14px") do
        div(style: "width:34px;height:34px;border-radius:10px;background:#{@meta[:tint]};" \
                   "display:flex;align-items:center;justify-content:center;flex-shrink:0;margin-top:1px") do
          span(style: "color:#{@meta[:color]};display:flex;width:16px;height:16px") do
            render UI::Icon.new(feat[:icon], class: "w-full h-full")
          end
        end
        div do
          p(style: "font-size:13.5px;font-weight:600;color:#111827;margin-bottom:4px") { plain feat[:label] }
          p(style: "font-size:12.5px;color:#6b7280;line-height:1.5") { plain feat[:desc] }
        end
      end
    end

    def default_meta
      {
        icon: :layers, color: "#374151", tint: "rgba(55,65,81,0.08)",
        nav: nil, phase: "P13",
        subtitle: "This section is under active development and will be available soon.",
        features: []
      }
    end
  end
end
