# frozen_string_literal: true

module Settings
  class AllowlistsPanel < ApplicationComponent
    include UI::Theme

    def initialize(ip_allowlists: [], msisdn_allowlists: [])
      @ip_allowlists     = ip_allowlists
      @msisdn_allowlists = msisdn_allowlists
    end

    def view_template
      div(class: "flex flex-col gap-5") do
        ip_allowlist_card
        msisdn_allowlist_card
      end
    end

    private

    # ── IP allowlist ──────────────────────────────────────────────────────────

    def ip_allowlist_card
      count = @ip_allowlists.size
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100") do
          div(class: "flex items-start gap-3") do
            div(class: "w-9 h-9 rounded-xl bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0 mt-px") do
              span(class: "flex w-[15px] h-[15px] text-gray-400") do
                render UI::Icon.new(:globe, class: "w-full h-full")
              end
            end
            div(class: "flex-1 min-w-0") do
              div(class: "flex items-center gap-2 mb-[2px]") do
                p(class: TYPE_TITLE) { plain "IP allowlist" }
                if count > 0
                  span(class: "text-[11px] font-semibold text-gray-500 bg-gray-100 px-[9px] py-[2px] rounded-full") do
                    plain "#{count} #{count == 1 ? 'entry' : 'entries'}"
                  end
                else
                  span(class: "badge-green text-[11px] font-semibold px-[9px] py-[2px] rounded-full") { plain "Open access" }
                end
              end
              p(class: TYPE_CAPTION) { plain "Restrict portal and API access to specific IP addresses or CIDR ranges." }
            end
            render UI::Button.new(variant: :secondary,
                   data: { action: "click->dialog#open", dialog_target_param: "add-ip-dialog" }) do
              render UI::Icon.new(:plus, class: ICON_SM)
              plain "Add IP"
            end
            add_ip_dialog
          end
        end

        if @ip_allowlists.empty?
          ip_empty_state
        else
          ip_active_callout(count)
          div(class: "divide-rows") do
            @ip_allowlists.each { |entry| ip_entry_row(entry) }
          end
        end
      end
    end

    def ip_empty_state
      div(class: "px-6 py-10 flex flex-col items-center text-center") do
        div(class: "w-10 h-10 rounded-xl icon-green flex items-center justify-center mb-3") do
          span(class: "flex w-[17px] h-[17px]") { render UI::Icon.new(:globe, class: "w-full h-full") }
        end
        p(class: "#{TYPE_BODY_MD} mb-1") { plain "Open access" }
        p(class: TYPE_CAPTION) { plain "All IP addresses can reach your portal and API. Add a CIDR to restrict access to known networks." }
      end
    end

    def ip_active_callout(count)
      div(class: "px-6 py-[11px] border-b border-amber-100 flex items-center gap-3",
          style: "background:rgba(217,119,6,0.04)") do
        span(class: "flex w-[13px] h-[13px] text-amber-500 flex-shrink-0") do
          render UI::Icon.new(:info_circle, class: "w-full h-full")
        end
        p(class: "text-[12px] text-amber-800") do
          plain "Access is restricted — only the #{count} listed #{count == 1 ? 'address' : 'addresses'} can reach your portal and API."
        end
      end
    end

    def ip_entry_row(entry)
      badge_label, badge_color, badge_bg = cidr_badge_attrs(entry.cidr)
      div(class: "group flex items-center gap-4 px-6 py-[14px] hover:bg-gray-50/50 transition-colors") do
        div(class: "w-[34px] h-[34px] rounded-[9px] bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0") do
          span(class: "flex w-[13px] h-[13px] text-gray-400") do
            render UI::Icon.new(:globe, class: "w-full h-full")
          end
        end
        div(class: "flex-1 min-w-0") do
          div(class: "flex items-center gap-2 mb-[3px]") do
            code(class: "#{TYPE_MONO} text-[12.5px]") { plain entry.cidr }
            span(class: "text-[10px] font-semibold px-[7px] py-[2px] rounded-full flex-shrink-0",
                 style: "color:#{badge_color};background:#{badge_bg}") { plain badge_label }
          end
          p(class: TYPE_CAPTION) do
            parts = []
            parts << entry.label if entry.label.present?
            parts << "by #{entry.created_by.presence || 'you'}"
            parts << entry.created_at.strftime("%d %b %Y")
            plain parts.join(" · ")
          end
        end
        div(class: "flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity flex-shrink-0") do
          copy_button(entry.cidr)
          remove_button(settings_remove_ip_path(entry), "Remove #{entry.cidr} from allowlist?")
        end
      end
    end

    def cidr_badge_attrs(cidr)
      prefix = cidr.include?("/") ? cidr.split("/").last.to_i : 32
      if prefix == 32       then [ "Single IP",        "#16a34a", "#f0fdf4" ]
      elsif prefix >= 24    then [ "/#{prefix} range",  "#d97706", "#fffbeb" ]
      else                       [ "/#{prefix} range",  "#dc2626", "#fef2f2" ]
      end
    end

    def add_ip_dialog
      dialog(id: "add-ip-dialog",
             class: "border-0 rounded-2xl p-0 shadow-2xl w-full max-w-[420px] bg-white") do
        div(class: "px-6 py-[22px] border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Add IP to allowlist" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Enter a single IP address or a CIDR range (e.g. 203.0.113.0/24)." }
        end
        form(action: settings_add_ip_path, method: "post",
             class: "px-6 py-[22px] flex flex-col gap-[14px]") do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          render UI::InputField.new(name: "cidr",  label: "IP address or CIDR", placeholder: "e.g. 203.0.113.0/24", required: true)
          render UI::InputField.new(name: "label", label: "Label (optional)",   placeholder: "e.g. Office network")
          div(class: "flex gap-[10px] justify-end mt-1") do
            render UI::Button.new(variant: :secondary,
                   data: { action: "click->dialog#close", dialog_target_param: "add-ip-dialog" }) do
              render UI::Icon.new(:x, class: ICON_SM)
              plain "Cancel"
            end
            render UI::Button.new(variant: :primary, type: "submit") do
              render UI::Icon.new(:plus, class: ICON_SM)
              plain "Add IP"
            end
          end
        end
      end
    end

    # ── MSISDN allowlist ──────────────────────────────────────────────────────

    def msisdn_allowlist_card
      count = @msisdn_allowlists.size
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100") do
          div(class: "flex items-start gap-3") do
            div(class: "w-9 h-9 rounded-xl bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0 mt-px") do
              span(class: "flex w-[15px] h-[15px] text-gray-400") do
                render UI::Icon.new(:phone, class: "w-full h-full")
              end
            end
            div(class: "flex-1 min-w-0") do
              div(class: "flex items-center gap-2 mb-[2px]") do
                p(class: TYPE_TITLE) { plain "MSISDN allowlist" }
                if count > 0
                  span(class: "text-[11px] font-semibold text-gray-500 bg-gray-100 px-[9px] py-[2px] rounded-full") do
                    plain "#{count} #{count == 1 ? 'number' : 'numbers'}"
                  end
                else
                  span(class: "badge-green text-[11px] font-semibold px-[9px] py-[2px] rounded-full") { plain "Open" }
                end
              end
              p(class: TYPE_CAPTION) { plain "Restrict which phone numbers can initiate MoMo payments via your integration." }
            end
            render UI::Button.new(variant: :secondary,
                   data: { action: "click->dialog#open", dialog_target_param: "add-msisdn-dialog" }) do
              render UI::Icon.new(:plus, class: ICON_SM)
              plain "Add number"
            end
            add_msisdn_dialog
          end
        end

        if @msisdn_allowlists.empty?
          msisdn_empty_state
        else
          msisdn_active_callout(count)
          div(class: "divide-rows") do
            @msisdn_allowlists.each { |entry| msisdn_entry_row(entry) }
          end
        end
      end
    end

    def msisdn_empty_state
      div(class: "px-6 py-10 flex flex-col items-center text-center") do
        div(class: "w-10 h-10 rounded-xl icon-green flex items-center justify-center mb-3") do
          span(class: "flex w-[17px] h-[17px]") { render UI::Icon.new(:phone, class: "w-full h-full") }
        end
        p(class: "#{TYPE_BODY_MD} mb-1") { plain "Payments open" }
        p(class: TYPE_CAPTION) { plain "Any phone number can initiate MoMo payments. Add numbers to restrict to known customers." }
      end
    end

    def msisdn_active_callout(count)
      div(class: "px-6 py-[11px] border-b flex items-center gap-3",
          style: "background:rgba(61,71,245,0.04);border-color:rgba(61,71,245,0.12)") do
        span(class: "flex w-[13px] h-[13px] flex-shrink-0", style: "color:#{BRAND}") do
          render UI::Icon.new(:info_circle, class: "w-full h-full")
        end
        p(class: "text-[12px]", style: "color:#3730a3") do
          plain "Payments are restricted — only the #{count} listed #{count == 1 ? 'number' : 'numbers'} can initiate MoMo payments."
        end
      end
    end

    def msisdn_entry_row(entry)
      telco = detect_telco(entry.msisdn)
      div(class: "group flex items-center gap-4 px-6 py-[14px] hover:bg-gray-50/50 transition-colors") do
        div(class: "w-[34px] h-[34px] rounded-[9px] bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0") do
          span(class: "flex w-[13px] h-[13px] text-gray-400") do
            render UI::Icon.new(:phone, class: "w-full h-full")
          end
        end
        div(class: "flex-1 min-w-0") do
          div(class: "flex items-center gap-2 mb-[3px]") do
            code(class: "#{TYPE_MONO} text-[12.5px]") { plain entry.msisdn }
            if telco
              t_name, t_color, t_bg = telco
              span(class: "text-[10px] font-semibold px-[7px] py-[2px] rounded-full flex-shrink-0",
                   style: "color:#{t_color};background:#{t_bg}") { plain t_name }
            end
          end
          p(class: TYPE_CAPTION) do
            parts = []
            parts << entry.label if entry.label.present?
            parts << "by #{entry.created_by.presence || 'you'}"
            parts << entry.created_at.strftime("%d %b %Y")
            plain parts.join(" · ")
          end
        end
        div(class: "flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity flex-shrink-0") do
          copy_button(entry.msisdn)
          remove_button(settings_remove_msisdn_path(entry), "Remove #{entry.msisdn} from allowlist?")
        end
      end
    end

    def detect_telco(msisdn)
      local  = msisdn.gsub(/\A\+233/, "0").gsub(/\A233/, "0")
      prefix = local[0, 3]
      case prefix
      when "024", "054", "055", "059" then [ "MTN",    "#92400e", "#fef3c7" ]
      when "020", "050"               then [ "Telecel", "#991b1b", "#fee2e2" ]
      when "027", "057", "026", "056" then [ "AT",      "#1e40af", "#dbeafe" ]
      end
    end

    # ── Shared helpers ────────────────────────────────────────────────────────

    def copy_button(value)
      button(type: "button",
             class: "flex w-7 h-7 rounded-lg items-center justify-center text-gray-300 " \
                    "hover:text-gray-600 hover:bg-gray-100 transition-colors border-0 bg-transparent cursor-pointer",
             onclick: "navigator.clipboard.writeText(this.dataset.val);this.classList.add('!text-green-600');setTimeout(()=>this.classList.remove('!text-green-600'),1200)",
             data: { val: value }) do
        span(class: "flex w-[13px] h-[13px]") { render UI::Icon.new(:copy, class: "w-full h-full") }
      end
    end

    def remove_button(path, confirm_text)
      form(action: path, method: "post", data: { turbo_confirm: confirm_text }) do
        input(type: "hidden", name: "_method",            value: "delete")
        input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
        button(type: "submit",
               class: "flex w-7 h-7 rounded-lg items-center justify-center text-gray-300 " \
                      "hover:text-red-500 hover:bg-red-50 transition-colors border-0 bg-transparent cursor-pointer") do
          span(class: "flex w-[13px] h-[13px]") { render UI::Icon.new(:x, class: "w-full h-full") }
        end
      end
    end

    def add_msisdn_dialog
      dialog(id: "add-msisdn-dialog",
             class: "border-0 rounded-2xl p-0 shadow-2xl w-full max-w-[420px] bg-white") do
        div(class: "px-6 py-[22px] border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Add phone number to allowlist" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Only allowlisted numbers can initiate MoMo payments." }
        end
        form(action: settings_add_msisdn_path, method: "post",
             class: "px-6 py-[22px] flex flex-col gap-[14px]") do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          render UI::InputField.new(name: "msisdn", label: "Phone number (MSISDN)", placeholder: "e.g. +233241234567", required: true)
          render UI::InputField.new(name: "label",  label: "Label (optional)",      placeholder: "e.g. VIP customer")
          div(class: "flex gap-[10px] justify-end mt-1") do
            render UI::Button.new(variant: :secondary,
                   data: { action: "click->dialog#close", dialog_target_param: "add-msisdn-dialog" }) do
              render UI::Icon.new(:x, class: ICON_SM)
              plain "Cancel"
            end
            render UI::Button.new(variant: :primary, type: "submit") do
              render UI::Icon.new(:plus, class: ICON_SM)
              plain "Add number"
            end
          end
        end
      end
    end
  end
end
