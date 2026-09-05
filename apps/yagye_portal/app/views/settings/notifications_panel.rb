# frozen_string_literal: true

module Settings
  class NotificationsPanel < ApplicationComponent
    include UI::Theme

    EVENTS = [
      { key: "payment_success",  label: "Payment received",   desc: "When a customer's payment settles" },
      { key: "payment_failed",   label: "Payment failed",     desc: "When a payment attempt fails" },
      { key: "dispute_opened",   label: "Dispute opened",     desc: "When a customer raises a dispute" },
      { key: "dispute_resolved", label: "Dispute resolved",   desc: "When a dispute is closed" },
      { key: "kyb_status",       label: "KYB status update",  desc: "When your KYB application status changes" },
      { key: "new_team_member",  label: "New team member",    desc: "When someone joins your team" },
      { key: "api_key_created",  label: "API key generated",  desc: "When a new API key is created" },
      { key: "login_new_device", label: "New device sign-in", desc: "When a sign-in occurs from a new browser or device" }
    ].freeze

    def initialize(current_user:)
      @current_user = current_user
    end

    def view_template
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Notification preferences" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Choose which events alert you and how you receive them." }
        end

        div(class: "px-6 py-5 border-b border-gray-100") do
          div(class: "flex items-center justify-between mb-[18px]") do
            p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest") { plain "Alert me when…" }
            a(href: "#", class: "text-[11px] font-semibold no-underline", style: "color:#{BRAND}") { plain "Select all" }
          end
          div(class: "flex flex-col") do
            EVENTS.each { |notif| event_row(notif) }
          end
        end

        div(class: "px-6 py-5 border-b border-gray-100") do
          p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-4") { plain "Delivery channels" }
          channel_row(:mail,  "Email",
                      "Send to #{@current_user&.email || 'your email address'}",
                      checked: true)
          channel_row(:bell,  "In-app",
                      "Alerts and badges inside the portal",
                      checked: true)
          channel_row(:phone, "SMS",
                      "Text message to your registered phone number",
                      coming_soon: true)
        end

        div(class: "px-6 py-4 bg-gray-50 border-t border-gray-100 flex justify-end") do
          render UI::Button.new(variant: :primary) do
            render UI::Icon.new(:check, class: ICON_SM)
            plain "Save preferences"
          end
        end
      end
    end

    private

    def event_row(notif)
      label(class: "flex items-center gap-4 py-[10px] px-3 -mx-3 rounded-xl hover:bg-gray-50/70 cursor-pointer transition-colors") do
        input(type: "checkbox", name: "notifications[#{notif[:key]}]", value: "1", checked: true,
              class: "flex-shrink-0 cursor-pointer rounded-[4px] w-[15px] h-[15px]",
              style: "accent-color:#{BRAND}")
        div(class: "flex-1 min-w-0") do
          p(class: TYPE_BODY_MD) { plain notif[:label] }
          p(class: TYPE_CAPTION) { plain notif[:desc] }
        end
      end
    end

    def channel_row(icon, label_text, desc, checked: false, coming_soon: false)
      div(class: "flex items-center gap-4 py-[13px] border-b border-gray-50 last:border-0 #{coming_soon ? 'opacity-50' : ''}") do
        div(class: "w-9 h-9 rounded-xl bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0") do
          span(class: "flex w-[15px] h-[15px] text-gray-400") do
            render UI::Icon.new(icon, class: "w-full h-full")
          end
        end
        div(class: "flex-1 min-w-0") do
          div(class: "flex items-center gap-2") do
            p(class: TYPE_BODY_MD) { plain label_text }
            if coming_soon
              span(class: "badge-gray text-[10px] font-semibold px-[7px] py-[2px] rounded-full") { plain "Coming soon" }
            end
          end
          p(class: TYPE_CAPTION) { plain desc }
        end
        render UI::Toggle.new(name: "channel_#{label_text.downcase}", checked: coming_soon ? false : checked)
      end
    end
  end
end
