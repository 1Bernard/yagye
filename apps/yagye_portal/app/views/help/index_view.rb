# frozen_string_literal: true

module Help
  class IndexView < ApplicationComponent
    include UI::Theme

    MERCHANT_GUIDES = [
      {
        icon:    :building,
        palette: "brand",
        title:   "Onboarding & KYB",
        desc:    "Complete your business verification, upload documents, and get approved to process live payments in Ghana."
      },
      {
        icon:    :wallet,
        palette: "green",
        title:   "Payments & Settlements",
        desc:    "Understand MoMo payment flows, settlement schedules, disputes, and how to read your transaction history."
      },
      {
        icon:    :shield,
        palette: "amber",
        title:   "Security & Access",
        desc:    "Set up 2FA, manage IP and MSISDN allowlists, issue API keys, and control your team's permissions."
      }
    ].freeze

    DEVELOPER_DOCS = [
      { icon: :file,   palette: "brand",  title: "API Reference",  desc: "Full REST API documentation with request and response examples." },
      { icon: :globe,  palette: "purple", title: "Webhooks Guide",  desc: "Receive signed events and verify HMAC-SHA256 signatures."        },
      { icon: :layers, palette: "teal",   title: "Testing Guide",   desc: "Sandbox MSISDNs, simulator endpoints, and test scenarios."       },
      { icon: :chart,  palette: "green",  title: "System Status",   desc: "Live uptime, latency metrics, and incident history."             },
      { icon: :tag,    palette: "amber",  title: "Changelog",        desc: "Recent product updates, API versions, and breaking changes."    },
      { icon: :users,  palette: "red",    title: "Community",        desc: "Developer forum, integration tips, and shared code samples."    }
    ].freeze

    FAQS = [
      {
        q: "When do settlements arrive in my bank account?",
        a: "Settlements process daily at the close of the business day (18:00 GMT) for all eligible payments. Funds typically clear within 1–2 business days depending on your bank. You can view individual settlement batches, their amounts, and status on the Settlements page under Payments."
      },
      {
        q: "Why is a payment showing as Pending?",
        a: "MoMo payments can sit in a Pending state when the telecom's callback is delayed or dropped before reaching Yagye. Our system automatically polls the provider for payments stuck beyond 90 seconds and resolves them to their true terminal state — no action needed on your part. If a payment remains pending beyond 10 minutes, contact support with the payment reference."
      },
      {
        q: "How do I restrict which customers can pay?",
        a: "Use the MSISDN allowlist in Settings → Allowlists. Once any number is added to the list, only those phone numbers can initiate MoMo payments through your integration. An empty list means any phone number can pay — this is the default and the recommended setting for most merchants."
      },
      {
        q: "What happens when a customer raises a dispute?",
        a: "You will receive an in-app notification and email immediately. You have 5 business days to submit evidence — transaction records, delivery confirmation, or customer communication. Disputes are reviewed within 10 business days. Funds are held in reserve until resolved. You can track all open disputes on the Disputes page."
      },
      {
        q: "How long does KYB verification take?",
        a: "Standard KYB review completes within 1–3 business days of submitting all required documents. Applications with multiple beneficial owners or foreign directors may take up to 5 business days. You will receive an email notification at each status change. Your account remains active in sandbox (test) mode throughout the review."
      },
      {
        q: "How do I test payments in the sandbox?",
        a: "Switch to Test mode using the toggle at the bottom of the sidebar. Use the documented sandbox MSISDNs — for example, 024 100 0001 always returns a successful MTN payment, and 024 100 0002 always fails. Test API keys are prefixed with sk_test_ and never touch real money or real telecoms."
      },
      {
        q: "How do I verify webhook signatures?",
        a: "Every webhook is signed with HMAC-SHA256 using your endpoint's secret. Compute HMAC-SHA256(secret, raw_body) and compare it to the X-Yagye-Signature header value. Always validate against the raw request body before parsing JSON. See the Webhooks Guide for copy-paste examples in Ruby, Python, and Node.js."
      }
    ].freeze

    def view_template
      render Layout::Shell.new(
        active_nav: :help,
        title:      "Help & Support",
        breadcrumbs: [ { label: "Help & Support" } ]
      ) do
        hero_section
        merchant_guides_section
        developer_docs_section
        faq_section
        support_section
      end
    end

    private

    # ── Hero ──────────────────────────────────────────────────────────────────

    def hero_section
      div(class: "text-center mb-10") do
        div(class: "inline-flex items-center gap-[6px] px-3 py-[5px] rounded-full border mb-5 status-operational") do
          div(class: "w-[7px] h-[7px] rounded-full flex-shrink-0 status-dot")
          span(class: "text-[12px] font-semibold status-text") { plain "All systems operational" }
        end

        h1(class: "text-[28px] font-bold text-gray-900 tracking-[-0.03em] mb-2") { plain "How can we help?" }
        p(class: "#{TYPE_BODY} max-w-md mx-auto mb-7") do
          plain "Search documentation, browse guides, or reach our support team directly."
        end

        div(class: "relative max-w-[520px] mx-auto") do
          span(class: "absolute left-[14px] top-1/2 -translate-y-1/2 flex w-[16px] h-[16px] text-gray-400 pointer-events-none") do
            render UI::Icon.new(:search, class: "w-full h-full")
          end
          input(type: "search",
                placeholder: "Search documentation and guides…",
                class: "w-full h-11 pl-[42px] pr-4 bg-white border border-gray-200 rounded-[11px] text-[13.5px] text-gray-900 placeholder-gray-400 outline-none",
                style: "box-shadow:0 1px 3px rgba(0,0,0,0.05)")
        end
      end
    end

    # ── Merchant guides ───────────────────────────────────────────────────────

    def merchant_guides_section
      div(class: "mb-8") do
        p(class: "#{TYPE_MICRO} mb-4") { plain "Merchant guides" }
        div(class: "grid grid-cols-3 gap-4") do
          MERCHANT_GUIDES.each { |guide| merchant_guide_card(guide) }
        end
      end
    end

    def merchant_guide_card(guide)
      p = guide[:palette]
      a(href: "#",
        class: "flex flex-col gap-4 p-5 bg-white border border-gray-100 rounded-2xl no-underline hover:border-gray-200 hover:shadow-sm transition-all group") do
        div(class: "w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0 icon-#{p}") do
          span(class: "flex w-[18px] h-[18px]") do
            render UI::Icon.new(guide[:icon], class: "w-full h-full")
          end
        end
        div do
          p(class: "#{TYPE_TITLE} mb-[5px]") { plain guide[:title] }
          p(class: TYPE_BODY) { plain guide[:desc] }
        end
        div(class: "flex items-center gap-[5px] mt-auto") do
          span(class: "text-[12px] font-semibold palette-#{p}") { plain "Learn more" }
          span(class: "flex w-[11px] h-[11px] palette-#{p} transition-transform group-hover:translate-x-0.5") do
            render UI::Icon.new(:arrow_right, class: "w-full h-full")
          end
        end
      end
    end

    # ── Developer resources ───────────────────────────────────────────────────

    def developer_docs_section
      div(class: "mb-8") do
        p(class: "#{TYPE_MICRO} mb-4") { plain "Developer resources" }
        div(class: "grid grid-cols-3 gap-4") do
          DEVELOPER_DOCS.each { |doc| developer_doc_card(doc) }
        end
      end
    end

    def developer_doc_card(doc)
      p = doc[:palette]
      a(href: "#",
        class: "flex items-start gap-4 p-5 bg-white border border-gray-100 rounded-2xl no-underline hover:border-gray-200 hover:shadow-sm transition-all") do
        div(class: "w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0 icon-#{p}") do
          span(class: "flex w-[15px] h-[15px]") do
            render UI::Icon.new(doc[:icon], class: "w-full h-full")
          end
        end
        div do
          p(class: "#{TYPE_BODY_MD} mb-[3px]") { plain doc[:title] }
          p(class: TYPE_CAPTION) { plain doc[:desc] }
        end
      end
    end

    # ── FAQ ───────────────────────────────────────────────────────────────────

    def faq_section
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden mb-5") do
        div(class: "grid",
            style: "grid-template-columns:220px 1fr") do
          div(class: "px-6 py-7 border-r border-gray-100") do
            p(class: "#{TYPE_TITLE} text-[15px] tracking-[-0.02em] mb-2") { plain "Common questions" }
            p(class: TYPE_BODY) do
              plain "Can't find the answer? Our support team is ready to help."
            end
            a(href: "mailto:support@yagye.com",
              class: "inline-flex items-center gap-[6px] mt-4 no-underline text-[12px] font-semibold",
              style: "color:#{BRAND}") do
              span(class: "flex w-[12px] h-[12px]") do
                render UI::Icon.new(:mail, class: "w-full h-full")
              end
              plain "support@yagye.com"
            end
          end

          div(class: "divide-rows") do
            FAQS.each { |faq| faq_item(faq) }
          end
        end
      end
    end

    def faq_item(faq)
      details(class: "group px-6") do
        summary(class: "flex items-center justify-between py-[15px] cursor-pointer select-none list-none [&::-webkit-details-marker]:hidden") do
          span(class: "#{TYPE_BODY_MD} pr-6 leading-snug") { plain faq[:q] }
          span(class: "flex-shrink-0 w-5 h-5 rounded-full flex items-center justify-center " \
                      "bg-gray-200 group-open:bg-[#3D47F5] transition-colors flex-shrink-0") do
            span(class: "flex w-[10px] h-[10px] text-gray-600 group-open:text-white transition-colors") do
              render UI::Icon.new(:plus, class: "w-full h-full")
            end
          end
        end
        div(class: "pb-5 -mt-1") do
          p(class: "#{TYPE_BODY} leading-relaxed") { plain faq[:a] }
        end
      end
    end

    # ── Support ───────────────────────────────────────────────────────────────

    def support_section
      div(class: "grid grid-cols-2 gap-4") do
        email_support_card
        sla_card
      end
    end

    def email_support_card
      div(class: "bg-white border border-gray-100 rounded-2xl p-6") do
        div(class: "flex items-center gap-3 mb-4") do
          div(class: "w-10 h-10 rounded-xl icon-blue flex items-center justify-center flex-shrink-0") do
            span(class: "flex w-[18px] h-[18px]") do
              render UI::Icon.new(:mail, class: "w-full h-full")
            end
          end
          p(class: TYPE_TITLE) { plain "Email support" }
        end
        p(class: "#{TYPE_CAPTION} mb-5") do
          plain "Our team is available Monday–Friday, 8 AM–6 PM GMT. We typically respond within 4 hours during business hours."
        end
        render UI::Button.new(variant: :primary, href: "mailto:support@yagye.com") do
          render UI::Icon.new(:mail, class: ICON_SM)
          plain "Contact support"
        end
      end
    end

    SLA_TIERS = [
      { badge: "Emergency", desc: "Service is completely down",       val: "< 1",  unit: "hour",          color: "#dc2626", palette: "red"   },
      { badge: "Urgent",    desc: "Payments aren't going through",    val: "< 4",  unit: "hours",         color: "#d97706", palette: "amber" },
      { badge: "Standard",  desc: "A feature isn't working as expected", val: "< 1", unit: "business day", color: "#3D47F5", palette: "brand" },
      { badge: "General",   desc: "You have a question or need guidance", val: "< 3", unit: "business days", color: "#6B7280", palette: "gray" }
    ].freeze

    def sla_card
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        # Header
        div(class: "p-6 border-b border-gray-50") do
          div(class: "flex items-center gap-3 mb-[6px]") do
            div(class: "w-10 h-10 rounded-xl icon-amber flex items-center justify-center flex-shrink-0") do
              span(class: "flex w-[18px] h-[18px]") do
                render UI::Icon.new(:clock, class: "w-full h-full")
              end
            end
            p(class: TYPE_TITLE) { plain "Response times" }
          end
          p(class: TYPE_CAPTION) do
            plain "Just tell us what's happening — we determine the urgency for you."
          end
        end
        # Rows
        div(class: "divide-rows") do
          SLA_TIERS.each { |tier| sla_row(tier) }
        end
        # Footer
        div(class: "px-5 py-3 bg-gray-100 border-t border-gray-100 flex items-center gap-2") do
          span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
            render UI::Icon.new(:clock, class: "w-full h-full")
          end
          p(class: "text-[11px] text-gray-400") do
            plain "Mon – Fri · 8 AM – 6 PM GMT · Urgent issues responded to 24 / 7"
          end
        end
      end
    end

    def sla_row(tier)
      div(class: "flex items-center gap-4 px-5 py-[13px]") do
        # Severity dot
        span(class: "w-[8px] h-[8px] rounded-full flex-shrink-0",
             style: "background:#{tier[:color]}") { }
        # Label + scenario
        div(class: "flex-1 min-w-0") do
          span(class: "badge-#{tier[:palette]} text-[11px] font-semibold px-[8px] py-[2px] rounded-full") do
            plain tier[:badge]
          end
          p(class: "#{TYPE_CAPTION} mt-[4px] leading-snug") { plain tier[:desc] }
        end
        # Time
        div(class: "text-right flex-shrink-0") do
          p(class: "text-[14px] font-bold tabular-nums leading-tight",
            style: "color:#{tier[:color]}") { plain tier[:val] }
          p(class: "text-[10.5px] text-gray-400 leading-tight") { plain tier[:unit] }
        end
      end
    end
  end
end
