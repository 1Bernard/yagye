# frozen_string_literal: true

module Settings
  class VerificationPanel < ApplicationComponent
    include UI::Theme

    TIERS = [
      { n: 1, label: "Basic",     limit: "GHS 1,000 / day",  short: "GHS 1,000/day" },
      { n: 2, label: "In Review", limit: "GHS 10,000 / day", short: "GHS 10,000/day" },
      { n: 3, label: "Verified",  limit: "No daily limit",   short: "Unlimited" }
    ].freeze

    DOCS_TIER1 = [
      "Valid government-issued photo ID",
      "Proof of address (utility bill or bank statement, < 3 months old)",
      "Certificate of incorporation"
    ].freeze

    TIMELINE = [
      { label: "Application submitted", sub: "KYB documents received by Yagye",          icon: :check_circle },
      { label: "Compliance review",     sub: "Our team is reviewing — usually 1–3 days", icon: :clock        },
      { label: "Limits unlocked",       sub: "No daily limit — all payment types enabled", icon: :unlock     }
    ].freeze

    def initialize(tier:)
      @tier = tier
    end

    def view_template
      div(class: "flex flex-col gap-5") do
        status_banner
        progress_card
        timeline_card if @tier == 2
        docs_card     if @tier == 1
        contact_row
      end
    end

    private

    def cfg
      @cfg ||= tier_config(@tier)
    end

    # ── Status banner ─────────────────────────────────────────────────────────

    def status_banner
      done_pct = @tier == 3 ? 100 : @tier == 2 ? 60 : 15
      deg      = (done_pct * 3.6).round(1)

      div(class: "rounded-2xl px-7 py-6 flex items-center gap-6",
          style: "background:#{cfg[:bg]};border:1px solid #{cfg[:border]}") do
        div(class: "w-[56px] h-[56px] rounded-full flex-shrink-0 flex items-center justify-center p-[5px]",
            style: "background:conic-gradient(#{cfg[:accent]} #{deg}deg, rgba(128,128,128,0.18) #{deg}deg)") do
          div(class: "w-full h-full rounded-full bg-white flex items-center justify-center") do
            span(class: "text-[11px] font-bold leading-none", style: "color:#{cfg[:accent]}") { plain "T#{@tier}" }
          end
        end

        div(class: "flex-1 min-w-0") do
          p(class: "text-[15px] font-bold text-gray-900 mb-0.5") { plain cfg[:title] }
          p(class: "#{TYPE_CAPTION} mb-3") { plain cfg[:subtitle] }
          div(class: "flex items-center gap-3") do
            div(class: "flex-1 h-[5px] rounded-full overflow-hidden", style: "background:rgba(128,128,128,0.15)") do
              div(class: "h-full rounded-full",
                  style: "width:#{done_pct}%;background:#{cfg[:accent]};transition:width 600ms ease")
            end
            span(class: "text-[11px] font-semibold tabular-nums flex-shrink-0",
                 style: "color:#{cfg[:accent]}") { plain "#{@tier} of 3" }
          end
        end

        if @tier == 1
          render UI::Button.new(variant: :primary, href: verify_path, data: { turbo_frame: "_top" }) do
            plain "Start verification →"
          end
        elsif @tier == 3
          span(class: "badge-green text-[12px] font-semibold px-3 py-1.5 rounded-full flex-shrink-0") do
            plain "Fully verified"
          end
        end
      end
    end

    # ── Tier progress card ────────────────────────────────────────────────────

    def progress_card
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Tier progression" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Completing each tier unlocks higher transaction limits." }
        end

        TIERS.each do |t|
          done    = t[:n] < @tier
          current = t[:n] == @tier

          div(class: "flex items-center gap-4 px-6 py-[15px] border-b border-gray-50 last:border-0") do
            if done
              div(class: "w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0",
                  style: "background:#{cfg[:icon_bg]};border:1px solid #{cfg[:icon_border]}") do
                span(class: "flex w-[14px] h-[14px]", style: "color:#{cfg[:accent]}") do
                  render UI::Icon.new(:check, class: "w-full h-full")
                end
              end
            elsif current
              div(class: "w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0",
                  style: "background:#{cfg[:icon_bg]};border:1.5px solid #{cfg[:accent]}") do
                div(style: "width:7px;height:7px;border-radius:50%;background:#{cfg[:accent]}")
              end
            else
              div(class: "w-8 h-8 rounded-xl bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0") do
                span(class: "text-[11px] font-bold text-gray-300") { plain t[:n].to_s }
              end
            end

            div(class: "flex-1 min-w-0") do
              p(class: "text-[13px] #{done || current ? 'font-semibold text-gray-900' : 'font-medium text-gray-400'}") do
                plain "Tier #{t[:n]} — #{t[:label]}"
              end
              p(class: TYPE_CAPTION) { plain t[:limit] }
            end

            if done
              span(class: "badge-green text-[11px] font-semibold px-[9px] py-[3px] rounded-full flex-shrink-0") { plain "Done" }
            elsif current
              span(class: "text-[11px] font-semibold px-[9px] py-[3px] rounded-full flex-shrink-0",
                   style: "background:#{cfg[:badge_bg]};color:#{cfg[:accent]}") { plain "Current" }
            else
              span(class: "badge-gray text-[11px] font-semibold px-[9px] py-[3px] rounded-full flex-shrink-0") { plain "Locked" }
            end
          end
        end
      end
    end

    # ── Review timeline card (Tier 2) ─────────────────────────────────────────

    def timeline_card
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Review status" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Track where your application is in the compliance process." }
        end

        div(class: "px-6 pt-[6px] pb-[10px]") do
          p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest pt-4 pb-3") { plain "Compliance" }

          TIMELINE.each_with_index do |step, i|
            done   = i < 1
            active = i == 1
            last   = i == TIMELINE.length - 1

            div(class: "flex items-center gap-3 #{last ? 'py-[12px]' : 'py-[12px] border-b border-gray-50'}") do
              div(class: "w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0",
                  style: "background:#{active ? cfg[:icon_bg] : (done ? 'rgba(22,163,74,0.08)' : '#F9FAFB')};border:#{active ? "1.5px solid #{cfg[:accent]}" : '1px solid #E5E7EB'}") do
                span(class: "flex w-[14px] h-[14px]",
                     style: "color:#{active ? cfg[:accent] : (done ? '#16a34a' : '#D1D5DB')}") do
                  render UI::Icon.new(step[:icon], class: "w-full h-full")
                end
              end

              div(class: "flex-1 min-w-0") do
                p(class: "text-[13px] #{active || done ? 'font-semibold text-gray-900' : 'font-medium text-gray-400'}") do
                  plain step[:label]
                end
                p(class: TYPE_CAPTION) { plain step[:sub] }
              end

              if done
                span(class: "badge-green text-[11px] font-semibold px-[9px] py-[3px] rounded-full flex-shrink-0") { plain "Done" }
              elsif active
                span(class: "text-[11px] font-semibold px-[9px] py-[3px] rounded-full flex-shrink-0",
                     style: "background:#{cfg[:badge_bg]};color:#{cfg[:accent]}") { plain "In progress" }
              else
                span(class: "badge-gray text-[11px] font-semibold px-[9px] py-[3px] rounded-full flex-shrink-0") { plain "Pending" }
              end
            end
          end
        end
      end
    end

    # ── Required documents card (Tier 1) ──────────────────────────────────────

    def docs_card
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Required documents" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") do
            plain "Upload these through the verification flow. "
            a(href: verify_path,
              style: "color:#{BRAND};font-weight:500;text-decoration:none") { plain "Start verification →" }
          end
        end

        div(class: "px-6 pt-[6px] pb-[10px]") do
          p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest pt-4 pb-3") { plain "Documents" }

          DOCS_TIER1.each_with_index do |doc, i|
            last = i == DOCS_TIER1.length - 1
            div(class: "flex items-center gap-3 #{last ? 'py-[12px]' : 'py-[12px] border-b border-gray-50'}") do
              div(class: "w-8 h-8 rounded-xl bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0") do
                span(class: "flex w-[14px] h-[14px] text-gray-400") do
                  render UI::Icon.new(:file, class: "w-full h-full")
                end
              end
              p(class: "text-[13px] font-medium text-gray-700 flex-1") { plain doc }
            end
          end
        end
      end
    end

    # ── Contact row ───────────────────────────────────────────────────────────

    def contact_row
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "flex items-center gap-4 px-6 py-[16px]") do
          div(class: "w-[34px] h-[34px] rounded-xl icon-brand flex items-center justify-center flex-shrink-0") do
            span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(:mail, class: "w-full h-full") }
          end
          div(class: "flex-1 min-w-0") do
            p(class: "text-[13px] font-semibold text-gray-800") { plain "Contact compliance team" }
            p(class: TYPE_CAPTION) do
              plain "Questions about your verification? We're available Monday – Friday, 9 AM – 6 PM GMT."
            end
          end
          render UI::Button.new(variant: :secondary, href: "mailto:compliance@yagye.com") do
            render UI::Icon.new(:mail, class: ICON_SM)
            plain "Send email"
          end
        end
      end
    end

    # ── Tier config ───────────────────────────────────────────────────────────

    def tier_config(tier)
      case tier
      when 3
        { accent: "#16a34a", bg: "rgba(22,163,74,0.07)", border: "rgba(22,163,74,0.25)",
          icon_bg: "rgba(22,163,74,0.08)", icon_border: "rgba(22,163,74,0.20)",
          badge_bg: "rgba(22,163,74,0.10)",
          title: "Account fully verified",
          subtitle: "No transaction limits — live payments are fully enabled." }
      when 2
        { accent: BRAND, bg: "rgba(61,71,245,0.06)", border: "rgba(61,71,245,0.18)",
          icon_bg: "rgba(61,71,245,0.08)", icon_border: "rgba(61,71,245,0.20)",
          badge_bg: "rgba(61,71,245,0.08)",
          title: "Account verification in progress",
          subtitle: "Yagye's compliance team is reviewing your documents." }
      else
        { accent: "#d97706", bg: "rgba(217,119,6,0.07)", border: "rgba(217,119,6,0.25)",
          icon_bg: "rgba(217,119,6,0.08)", icon_border: "rgba(217,119,6,0.20)",
          badge_bg: "rgba(217,119,6,0.08)",
          title: "Verification required",
          subtitle: "Submit your identity documents to unlock higher transaction limits." }
      end
    end
  end
end
