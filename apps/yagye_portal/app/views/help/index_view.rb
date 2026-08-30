# frozen_string_literal: true

module Help
  class IndexView < ApplicationComponent
    include UI::Theme

    QUICK_LINKS = [
      { icon: :file,    title: "API Reference",  desc: "Full REST API documentation with examples.",    href: "#",
        color: "#3D47F5", tint: "rgba(61,71,245,0.08)" },
      { icon: :globe,   title: "Webhooks Guide", desc: "Receive events and verify signatures.",          href: "#",
        color: "#6d28d9", tint: "rgba(109,40,217,0.08)" },
      { icon: :layers,  title: "Testing Guide",  desc: "Sandbox credentials and test scenarios.",        href: "#",
        color: "#0d9488", tint: "rgba(13,148,136,0.08)" },
      { icon: :chart,   title: "System Status",  desc: "Live uptime and incident history.",               href: "#",
        color: "#16a34a", tint: "rgba(22,163,74,0.08)" },
      { icon: :tag,     title: "Changelog",      desc: "Recent product updates and API changes.",        href: "#",
        color: "#d97706", tint: "rgba(217,119,6,0.08)" },
      { icon: :users,   title: "Community",      desc: "Developer forum and integration tips.",          href: "#",
        color: "#dc2626", tint: "rgba(220,38,38,0.08)" }
    ].freeze

    def view_template
      render Layout::Shell.new(
        active_nav: :help,
        title:      "Help & Support",
        breadcrumbs: [ { label: "Help & Support" } ]
      ) do
        search_section
        quick_links_section
        support_section
      end
    end

    private

    def search_section
      div(style: "margin-bottom:32px") do
        div(style: "display:flex;align-items:center;gap:12px;margin-bottom:14px") do
          div(style: "display:flex;align-items:center;gap:6px;padding:5px 12px;" \
                     "background:#f0fdf4;border:1px solid #bbf7d0;border-radius:20px") do
            div(style: "width:7px;height:7px;border-radius:50%;background:#16a34a")
            span(style: "font-size:12px;font-weight:600;color:#15803d") { "All systems operational" }
          end
        end
        div(style: "position:relative;max-width:560px") do
          span(style: "position:absolute;left:16px;top:50%;transform:translateY(-50%);" \
                      "display:flex;width:18px;height:18px;color:#{SUBTLE_TEXT}") do
            render UI::Icon.new(:search, class: "w-full h-full")
          end
          input(type: "search",
                placeholder: "Search documentation, guides, and FAQs…",
                class: INPUT_FIELD,
                style: "padding-left:46px;font-size:14px")
        end
      end
    end

    def quick_links_section
      div(style: "margin-bottom:32px") do
        p(style: "#{TYPE_MICRO};margin-bottom:16px") { "Documentation" }
        div(style: "display:grid;grid-template-columns:repeat(3,1fr);gap:16px") do
          QUICK_LINKS.each { |link| quick_link_card(link) }
        end
      end
    end

    def quick_link_card(link)
      a(href: link[:href],
        style: "display:flex;gap:16px;padding:20px;background:#fff;border:1px solid #{BORDER};" \
               "border-radius:16px;text-decoration:none;transition:border-color 150ms,box-shadow 150ms") do
        div(style: "width:40px;height:40px;border-radius:12px;background:#{link[:tint]};" \
                   "display:flex;align-items:center;justify-content:center;flex-shrink:0;flex-shrink:0") do
          span(style: "display:flex;width:18px;height:18px;color:#{link[:color]}") do
            render UI::Icon.new(link[:icon], class: "w-full h-full")
          end
        end
        div do
          p(style: "#{TYPE_BODY_MD};margin-bottom:3px") { link[:title] }
          p(style: TYPE_CAPTION) { link[:desc] }
        end
      end
    end

    def support_section
      div(style: "display:grid;grid-template-columns:1fr 1fr;gap:20px") do
        email_support_card
        sla_card
      end
    end

    def email_support_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;padding:24px") do
        div(style: "display:flex;align-items:center;gap:12px;margin-bottom:16px") do
          div(style: "width:40px;height:40px;border-radius:12px;background:#eff6ff;" \
                     "display:flex;align-items:center;justify-content:center;flex-shrink:0") do
            span(style: "display:flex;width:18px;height:18px;color:#3b82f6") do
              render UI::Icon.new(:mail, class: "w-full h-full")
            end
          end
          p(style: TYPE_TITLE) { "Email support" }
        end
        p(style: "#{TYPE_BODY};margin-bottom:16px") do
          "Our support team is available Monday–Friday, 8 AM–6 PM GMT."
        end
        a(href: "mailto:support@yagye.com", class: BTN_PRIMARY, style: "text-decoration:none;display:inline-flex") do
          render UI::Icon.new(:mail, class: ICON_SM)
          "Contact support"
        end
      end
    end

    def sla_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;padding:24px") do
        div(style: "display:flex;align-items:center;gap:12px;margin-bottom:16px") do
          div(style: "width:40px;height:40px;border-radius:12px;background:#fef9c3;" \
                     "display:flex;align-items:center;justify-content:middle;flex-shrink:0") do
            span(style: "display:flex;width:18px;height:18px;color:#ca8a04") do
              render UI::Icon.new(:clock, class: "w-full h-full")
            end
          end
          p(style: TYPE_TITLE) { "Response times" }
        end
        div(style: "display:flex;flex-direction:column;gap:10px") do
          sla_row("Critical (P1)",  "< 1 hour",    "#dc2626")
          sla_row("High (P2)",      "< 4 hours",   "#f59e0b")
          sla_row("Standard (P3)",  "< 1 business day", INK)
          sla_row("Low (P4)",       "< 3 business days", MUTED_TEXT)
        end
      end
    end

    def sla_row(priority, time, color)
      div(style: "display:flex;align-items:center;justify-content:space-between") do
        p(style: "font-size:12.5px;font-weight:500;color:#{color}") { priority }
        p(style: TYPE_CAPTION) { time }
      end
    end
  end
end
