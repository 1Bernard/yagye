require "base64"

module Auth
  class Shell < ApplicationComponent
    BLUE = "#3D47F5"

    # White SVG wordmark logos — unified on the blue background (premium logo-strip standard)
    NETWORK_LOGOS = {
      "MTN MoMo" => <<~SVG,
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 82 26">
          <rect width="36" height="26" rx="4" fill="rgba(255,255,255,0.18)" stroke="rgba(255,255,255,0.7)" stroke-width="1"/>
          <text x="18" y="18" font-family="Arial Black,Arial,sans-serif" font-size="11" font-weight="900" fill="white" text-anchor="middle" letter-spacing="-0.5">MTN</text>
          <text x="60" y="18" font-family="Arial,sans-serif" font-size="12" font-weight="700" fill="white" text-anchor="middle">MoMo</text>
        </svg>
      SVG
      "Airtel" => <<~SVG,
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 26">
          <path d="M8 20 Q16 4 24 14 Q30 22 38 10" fill="none" stroke="white" stroke-width="2.5" stroke-linecap="round"/>
          <text x="24" y="24" font-family="Arial,sans-serif" font-size="10" font-weight="800" fill="white" text-anchor="middle" letter-spacing="-0.2">airtel</text>
        </svg>
      SVG
      "Stripe" => <<~SVG,
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 62 26">
          <rect width="22" height="26" rx="4" fill="rgba(255,255,255,0.18)" stroke="rgba(255,255,255,0.7)" stroke-width="1"/>
          <text x="11" y="18" font-family="Arial Black,Arial,sans-serif" font-size="14" font-weight="900" fill="white" text-anchor="middle">S</text>
          <text x="43" y="18" font-family="Arial,sans-serif" font-size="12" font-weight="700" fill="white" text-anchor="middle" letter-spacing="-0.3">stripe</text>
        </svg>
      SVG
      "Paystack" => <<~SVG,
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 82 26">
          <rect width="22" height="26" rx="4" fill="rgba(255,255,255,0.18)" stroke="rgba(255,255,255,0.7)" stroke-width="1"/>
          <text x="11" y="18" font-family="Arial Black,Arial,sans-serif" font-size="14" font-weight="900" fill="white" text-anchor="middle">P</text>
          <text x="53" y="18" font-family="Arial,sans-serif" font-size="12" font-weight="700" fill="white" text-anchor="middle" letter-spacing="-0.3">Paystack</text>
        </svg>
      SVG
      "Flutterwave" => <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 104 26">
          <path d="M4 20 Q8 8 12 16 Q16 24 20 12" fill="none" stroke="white" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
          <text x="62" y="18" font-family="Arial,sans-serif" font-size="11" font-weight="700" fill="white" text-anchor="middle" letter-spacing="-0.2">flutterwave</text>
        </svg>
      SVG
    }.freeze

    ROUTES = [
      { init: "M", name: "MTN MoMo",    vol: "HIGH",   suc: "94.2%", fail: "0.8%", bar: 88, color: "#0ea5e9", amount: "₵ 12.4M" },
      { init: "S", name: "Stripe",       vol: "HIGH",   suc: "99.1%", fail: "0.2%", bar: 72, color: "#6366f1", amount: "₵ 8.7M"  },
      { init: "A", name: "Airtel Tigo",  vol: "MEDIUM", suc: "89.3%", fail: "2.1%", bar: 40, color: "#f59e0b", amount: "₵ 3.2M"  },
      { init: "P", name: "Paystack",     vol: "HIGH",   suc: "97.6%", fail: "0.4%", bar: 60, color: "#8b5cf6", amount: "₵ 6.1M"  },
      { init: "F", name: "Flutterwave",  vol: "MEDIUM", suc: "95.8%", fail: "1.2%", bar: 55, color: "#10b981", amount: "₵ 5.5M"  },
      { init: "V", name: "Visa / Card",  vol: "LOW",    suc: "98.9%", fail: "0.3%", bar: 30, color: "#ef4444", amount: "₵ 2.8M"  }
    ].freeze

    MEMBERS = [
      { name: "Kofi Mensah",  sub: "2 merchants", role: "Owner",  new: true,  color: "#6366f1" },
      { name: "Ama Owusu",    sub: "1 merchant",  role: "Editor", new: false, color: "#f59e0b" },
      { name: "John Asante",  sub: "2 merchants", role: "Editor", new: false, color: "#10b981" }
    ].freeze

    AVATAR_SVGS = [
      # Kofi — dark skin, short hair, indigo bg
      %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40"><circle cx="20" cy="20" r="20" fill="#6366f1"/><ellipse cx="20" cy="38" rx="14" ry="10" fill="#4f46e5"/><circle cx="20" cy="19" r="9" fill="#6B3A2A"/><ellipse cx="20" cy="11" rx="9.5" ry="6.5" fill="#1A0500"/><circle cx="16.5" cy="18" r="1.6" fill="#0d0d0d"/><circle cx="23.5" cy="18" r="1.6" fill="#0d0d0d"/><path d="M17 22.5 Q20 24.5 23 22.5" stroke="#4A2010" stroke-width="1.2" fill="none" stroke-linecap="round"/></svg>),
      # Ama — medium skin, longer hair, amber bg
      %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40"><circle cx="20" cy="20" r="20" fill="#f59e0b"/><ellipse cx="20" cy="38" rx="14" ry="10" fill="#d97706"/><ellipse cx="11" cy="21" rx="3.5" ry="10" fill="#1A0500"/><ellipse cx="29" cy="21" rx="3.5" ry="10" fill="#1A0500"/><circle cx="20" cy="19" r="9" fill="#C68642"/><ellipse cx="20" cy="10" rx="10" ry="6" fill="#1A0500"/><circle cx="16.5" cy="18" r="1.6" fill="#0d0d0d"/><circle cx="23.5" cy="18" r="1.6" fill="#0d0d0d"/><path d="M17 22.5 Q20 24.5 23 22.5" stroke="#8B5E3C" stroke-width="1.2" fill="none" stroke-linecap="round"/></svg>),
      # John — medium-dark skin, short hair, emerald bg
      %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40"><circle cx="20" cy="20" r="20" fill="#10b981"/><ellipse cx="20" cy="38" rx="14" ry="10" fill="#059669"/><circle cx="20" cy="19" r="9" fill="#8B5E3C"/><ellipse cx="20" cy="11.5" rx="9" ry="6" fill="#1A0500"/><circle cx="16.5" cy="18" r="1.6" fill="#0d0d0d"/><circle cx="23.5" cy="18" r="1.6" fill="#0d0d0d"/><path d="M17 22.5 Q20 24.5 23 22.5" stroke="#6B4226" stroke-width="1.2" fill="none" stroke-linecap="round"/></svg>)
    ].freeze

    def initialize(title:, subtitle: nil)
      @title    = title
      @subtitle = subtitle
    end

    def view_template
      content_for(:body_class) { "h-screen overflow-hidden" }
      style { raw safe("html,body{margin:0;padding:0}") }
      div class: "fixed inset-0 flex bg-white" do
        left_panel { yield }
        right_section
      end
      render UI::Flash.new(flash: flash)
    end

    private

    # ── Left panel ────────────────────────────────────────────────────────────

    def left_panel(&content)
      div class: "flex-1 flex flex-col px-14 py-12 overflow-y-auto" do
        # Logo — top edge, outer py-12 is its breathing room
        div class: "shrink-0" do
          img src: asset_path("yagye-text.png"), alt: "Yagye", class: "h-8 w-auto"
        end

        # Equal spacer — pushes form to vertical centre
        div class: "flex-1"

        # Form block — centred horizontally, never touches logo or footer
        div class: "shrink-0 flex flex-col items-center" do
          div class: "w-full max-w-[360px]" do
            h1 class: "text-[36px] font-extrabold text-gray-900 leading-[1.08] tracking-[-0.03em] mb-2" do
              plain @title
            end
            if @subtitle
              p class: "text-[13.5px] text-gray-600 leading-[1.5] mb-3" do
                plain @subtitle
              end
            end
            div class: "inline-flex items-center gap-1.5 mb-8 px-2.5 py-1 rounded-full bg-gray-50 border border-gray-100" do
              div class: "w-1.5 h-1.5 rounded-full bg-emerald-400"
              span class: "text-[11px] text-gray-600 font-medium" do
                plain "2,500+ merchants across West Africa"
              end
            end
            content.call
          end
        end

        # Equal spacer — mirrors the one above, keeps form centred
        div class: "flex-1"

        # Copyright — bottom edge, outer py-12 is its breathing room
        p class: "shrink-0 text-[11px] text-gray-400 text-center w-full" do
          plain "© #{Time.current.year} Yagye Technologies. All rights reserved."
        end
      end
    end

    # ── Right section — floating blue card with margin on all 4 sides ─────────

    def right_section
      div class: "w-[52%] shrink-0 p-7" do
        div class: "h-full flex flex-col rounded-[20px] overflow-hidden",
            style: "background-color:#{BLUE}" do
          # headline
          div class: "shrink-0 px-8 pt-8 pb-5" do
            p class: "text-[9px] font-bold uppercase tracking-[0.16em] mb-2",
              style: "color:rgba(255,255,255,0.55)" do
              plain "Africa's Payment Layer"
            end
            h2 class: "text-[24px] font-extrabold text-white leading-[1.15] tracking-[-0.02em] mb-2" do
              plain "The simplest way to"
              br
              plain "pay across Africa"
            end
            p class: "text-[12px] leading-[1.5]",
              style: "color:rgba(255,255,255,0.82)" do
              plain "Enter your credentials to access your account"
            end
          end

          # cards area — both cards absolutely positioned, vertically centred
          div class: "flex-1 relative overflow-hidden" do
            # main dashboard card — pinned from top so full invite card is visible
            div class: "absolute",
                style: "top:6%;left:32px;width:58%" do
              div class: "bg-white rounded-[14px] shadow-xl overflow-hidden flex flex-col" do
                dashboard_topbar
                dashboard_stats
                dashboard_table
              end
            end

            # overlay invite card — vertically centred
            div class: "absolute z-10",
                style: "top:50%;transform:translateY(-50%);right:28px;width:46%" do
              div class: "bg-white rounded-[14px] shadow-2xl overflow-hidden" do
                invite_card
              end
            end
          end

          # partner logos
          div class: "shrink-0 px-8 pt-4 pb-6",
              style: "border-top:1px solid rgba(255,255,255,0.1)" do
            p class: "text-[9px] font-bold uppercase tracking-[0.18em] mb-2.5",
              style: "color:rgba(255,255,255,0.45)" do
              plain "Supported Networks"
            end
            div class: "flex items-center gap-4" do
              NETWORK_LOGOS.each_value do |svg|
                img src: "data:image/svg+xml;base64,#{Base64.strict_encode64(svg.strip)}",
                    class: "h-[18px] w-auto object-contain",
                    style: "opacity:0.78"
              end
            end
          end
        end
      end
    end

    # ── Dashboard card sections ───────────────────────────────────────────────

    def dashboard_topbar
      div class: "shrink-0 flex items-center gap-2 px-5 py-3.5 border-b border-gray-100" do
        chip("All Merchants ▾")

        div class: "ml-auto flex items-center gap-2.5" do
          div class: "flex -space-x-1.5" do
            AVATAR_SVGS.each do |svg|
              img src: "data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}",
                  class: "w-6 h-6 rounded-full ring-2 ring-white object-cover"
            end
          end
          span class: "text-[10px] font-semibold text-white rounded-lg px-3 py-1.5",
               style: "background:#{BLUE}" do
            plain "Add members ↑"
          end
        end
      end
    end

    def chip(text)
      span class: "inline-flex items-center text-[11px] text-gray-500 font-medium border border-gray-200 rounded-lg px-3 py-1.5 bg-white whitespace-nowrap" do
        raw safe(text.gsub("  ", "  "))
      end
    end

    def dashboard_stats
      div class: "shrink-0 grid grid-cols-2 divide-x divide-gray-100 border-b border-gray-100" do
        stat_tile("Productive Time / Day", "12.4 hr", "+23% last week",
                  [ 22, 28, 24, 36, 30, 44, 40, 52, 48, 60 ], BLUE, "sg_blue")
        stat_tile("Success Rate",          "99.2%",   "+0.3% last week",
                  [ 55, 60, 57, 64, 62, 70, 68, 72, 74, 78 ], "#10b981", "sg_green")
      end
    end

    def stat_tile(label, value, change, pts, color, grad_id)
      div class: "relative px-4 py-3 overflow-hidden" do
        p class: "text-[10px] text-gray-400 font-medium mb-1" do plain label end
        p class: "text-[22px] font-bold text-gray-900 leading-none mb-2" do plain value end
        div class: "flex items-center gap-1.5" do
          span class: "inline-flex items-center justify-center w-4 h-4 rounded-full text-[8px] font-bold text-white",
               style: "background:#22c55e" do
            plain "↑"
          end
          span class: "text-[10px] font-semibold text-green-600" do plain change end
        end
        div class: "absolute right-4 top-4 w-[78px] h-[46px]" do
          raw safe(sparkline_svg(pts, color, grad_id))
        end
      end
    end

    def dashboard_table
      div class: "shrink-0 flex flex-col" do
        div class: "shrink-0 px-5 pt-3 pb-2 flex items-center justify-between" do
          span class: "text-[11px] font-bold text-gray-800 tracking-tight" do
            plain "Team's Utilization"
          end
        end

        # Column headers
        div class: "shrink-0 grid items-center px-5 pb-2 border-b border-gray-100",
            style: "grid-template-columns: 2fr 1.1fr 1fr 1.5fr" do
          [ "Team Name", "Overall Utilization", "Over Utilized", "Under Util..." ].each do |h|
            span class: "text-[9px] text-gray-400 font-semibold uppercase tracking-wide truncate" do
              plain h
            end
          end
        end

        ROUTES.each_with_index { |r, i| route_row(r, i) }
      end
    end

    def route_row(r, i)
      row_bg    = i.odd? ? "background:#fff" : "background:#fafafa"
      vol_style = case r[:vol]
      when "HIGH"   then "background:#fee2e2;color:#dc2626"
      when "MEDIUM" then "background:#fef9c3;color:#ca8a04"
      else               "background:#dcfce7;color:#16a34a"
      end

      div class: "shrink-0 grid items-center px-5 border-b border-gray-50",
          style: "grid-template-columns:2fr 1.1fr 1fr 1.5fr; #{row_bg}" do
        # Name + avatar
        div class: "flex items-center gap-2.5 py-2" do
          div class: "w-[26px] h-[26px] rounded-full flex items-center justify-center text-[9px] font-bold text-white shrink-0",
              style: "background:#{r[:color]}" do
            plain r[:init]
          end
          span class: "text-[11px] font-semibold text-gray-700 truncate" do plain r[:name] end
        end

        # Volume badge
        div class: "flex items-center" do
          span class: "inline-flex items-center gap-1 text-[9px] font-bold px-2 py-0.5 rounded",
               style: vol_style do
            span class: "inline-block w-1.5 h-1.5 rounded-sm", style: "background:currentColor;opacity:0.7"
            plain r[:vol]
          end
        end

        # Success rate
        span class: "text-[11px] font-medium text-gray-600 tabular-nums" do plain r[:suc] end

        # Bar + amount
        div class: "flex items-center gap-2 pr-1" do
          div class: "flex-1 h-2 rounded-full overflow-hidden", style: "background:#e5e7eb" do
            div class: "h-full rounded-full", style: "width:#{r[:bar]}%;background:#{BLUE}"
          end
          span class: "text-[10px] text-gray-500 shrink-0 w-12 text-right tabular-nums font-medium" do
            plain r[:amount]
          end
        end
      end
    end

    # ── Overlay invite card ───────────────────────────────────────────────────

    def invite_card
      div class: "flex items-center justify-between px-4 py-3.5 border-b border-gray-100" do
        span class: "text-[12px] font-bold text-gray-900 tracking-tight" do plain "Add Member" end
        span class: "text-[18px] text-gray-300 leading-none cursor-pointer hover:text-gray-400" do plain "×" end
      end

      div class: "px-4 pt-3 pb-3.5 border-b border-gray-100" do
        p class: "text-[10px] font-semibold text-gray-500 mb-2" do plain "Email" end
        div class: "flex items-center gap-1.5" do
          div class: "flex-1 flex items-center justify-between border border-gray-200 rounded-lg px-3 py-2 bg-white min-w-0" do
            span class: "text-[10px] text-gray-600 truncate" do plain "rafiqur51@gmail.com" end
            span class: "text-[10px] text-gray-400 ml-1 shrink-0" do plain "⊕" end
          end
          div class: "shrink-0 text-[10px] font-semibold text-white rounded-lg px-2.5 py-2 border",
              style: "background:#{BLUE};border-color:#{BLUE}" do
            plain "Viewer ▾"
          end
          div class: "shrink-0 text-[10px] font-semibold text-white rounded-lg px-2.5 py-2",
              style: "background:#{BLUE}" do
            plain "Send Invite"
          end
        end
      end

      div class: "px-4 pt-3 pb-2 border-b border-gray-100" do
        p class: "text-[10px] font-semibold text-gray-500 mb-3" do plain "Members" end
        MEMBERS.each_with_index do |m, i|
          div class: "flex items-center gap-2.5 mb-3" do
            img src: "data:image/svg+xml;base64,#{Base64.strict_encode64(AVATAR_SVGS[i])}",
                class: "w-8 h-8 rounded-full object-cover shrink-0"
            div class: "flex-1 min-w-0" do
              div class: "flex items-center gap-1.5 mb-0.5" do
                span class: "text-[11px] font-semibold text-gray-800" do plain m[:name] end
                if m[:new]
                  span class: "text-[8px] font-bold text-blue-700 bg-blue-50 border border-blue-100 px-1 py-0.5 rounded" do
                    plain "new"
                  end
                end
              end
              span class: "text-[10px] text-gray-400" do plain m[:sub] end
            end
            span class: "shrink-0 text-[10px] text-gray-500 font-medium" do plain "#{m[:role]} ▾" end
          end
        end
      end

      div class: "px-4 py-3.5" do
        p class: "text-[10px] font-semibold text-gray-500 mb-2" do plain "Copy Link" end
        div class: "flex items-center gap-1.5" do
          div class: "flex-1 border border-gray-200 rounded-lg px-3 py-2 bg-gray-50 min-w-0" do
            span class: "text-[10px] text-gray-400 truncate block" do
              plain "portal.yagye.com/invite/abc123xyz"
            end
          end
          div class: "shrink-0 text-[10px] font-semibold text-white rounded-lg px-3 py-2",
              style: "background:#{BLUE}" do
            plain "Copy"
          end
        end
      end
    end

    # ── Inline SVG sparkline ──────────────────────────────────────────────────

    def sparkline_svg(pts, color, grad_id = nil)
      grad_id ||= "sg_#{color.delete('#')}"
      lo  = pts.min.to_f
      hi  = pts.max.to_f
      rng = (hi - lo).nonzero? || 1.0
      w   = 72
      h   = 44
      step = w.to_f / (pts.length - 1)

      coords = pts.each_with_index.map do |v, i|
        x = (i * step).round(2)
        y = (h - ((v - lo) / rng * h * 0.78) - h * 0.11).round(2)
        [ x, y ]
      end

      d = coords.each_with_index.map do |(x, y), i|
        if i == 0
          "M#{x},#{y}"
        else
          px, py = coords[i - 1]
          mx = ((x + px) / 2).round(2)
          "C#{mx},#{py} #{mx},#{y} #{x},#{y}"
        end
      end.join(" ")

      area = "#{d} L#{coords.last[0]},#{h} L0,#{h} Z"

      <<~SVG
        <svg viewBox="0 0 #{w} #{h}" fill="none" xmlns="http://www.w3.org/2000/svg" style="overflow:visible">
          <defs>
            <linearGradient id="#{grad_id}" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stop-color="#{color}" stop-opacity="0.25"/>
              <stop offset="100%" stop-color="#{color}" stop-opacity="0"/>
            </linearGradient>
          </defs>
          <path d="#{area}" fill="url(##{grad_id})" />
          <path d="#{d}" stroke="#{color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
          <circle cx="#{coords.last[0]}" cy="#{coords.last[1]}" r="3" fill="#{color}"/>
        </svg>
      SVG
    end
  end
end
