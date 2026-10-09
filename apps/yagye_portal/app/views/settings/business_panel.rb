# frozen_string_literal: true

module Settings
  class BusinessPanel < ApplicationComponent
    include UI::Theme

    def initialize(branding:, merchant:)
      @branding = branding
      @merchant = merchant
    end

    def view_template
      div(class: "flex flex-col gap-5") do
        logo_card
        details_card
      end
    end

    private

    # ── Logo ──────────────────────────────────────────────────────────────────

    def logo_card
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Business logo" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") do
            plain "Displayed on your payment links, checkout pages and invoices."
          end
        end

        div(class: "px-6 py-6 flex items-center gap-6") do
          # Logo preview
          logo_preview_box

          # Upload / remove actions
          div(class: "flex flex-col gap-3") do
            form(action: settings_merchant_branding_path, method: "post",
                 enctype: "multipart/form-data") do
              input(type: "hidden", name: "_method",            value: "patch")
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              div(class: "flex items-center gap-3") do
                label(for: "logo_file",
                      class: "inline-flex items-center gap-2 px-4 py-2 rounded-[10px] border border-gray-200 " \
                             "bg-white text-[13px] font-medium text-gray-700 hover:bg-gray-50 " \
                             "transition-colors cursor-pointer",
                      style: "line-height:1.4") do
                  span(class: "flex w-[14px] h-[14px] text-gray-500 flex-shrink-0") do
                    render UI::Icon.new(:upload, class: "w-full h-full")
                  end
                  plain "Upload logo"
                end
                input(id: "logo_file", type: "file", name: "logo",
                      accept: "image/png,image/jpeg,image/jpg,image/svg+xml,image/webp",
                      class: "sr-only",
                      data: { controller: "file-upload", action: "change->file-upload#submit" })
              end
            end

            if @branding&.logo&.attached?
              form(action: settings_remove_merchant_logo_path, method: "post",
                   data: { turbo_confirm: "Remove your logo?" }) do
                input(type: "hidden", name: "_method",            value: "delete")
                input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                button(type: "submit",
                       class: "text-[12.5px] font-medium text-red-500 hover:text-red-700 " \
                              "bg-transparent border-0 p-0 cursor-pointer transition-colors text-left") do
                  plain "Remove logo"
                end
              end
            end

            p(class: TYPE_CAPTION) do
              plain "PNG, JPEG, SVG or WebP. Recommended: 256 × 256 px or larger, square."
            end
          end
        end
      end
    end

    def logo_preview_box
      if @branding&.logo&.attached?
        div(class: "w-[72px] h-[72px] rounded-2xl border border-gray-200 flex items-center justify-center overflow-hidden bg-white flex-shrink-0") do
          img(src: @branding.logo_url, alt: "Business logo",
              class: "w-full h-full object-contain")
        end
      else
        div(class: "w-[72px] h-[72px] rounded-2xl border border-dashed border-gray-200 " \
                   "flex items-center justify-center flex-shrink-0 bg-gray-50") do
          div(class: "flex flex-col items-center gap-1") do
            span(class: "flex w-6 h-6 text-gray-300") do
              render UI::Icon.new(:upload, class: "w-full h-full")
            end
            span(class: "text-[9.5px] font-medium text-gray-300 text-center leading-tight") { plain "No logo" }
          end
        end
      end
    end

    # ── Details ───────────────────────────────────────────────────────────────

    def details_card
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Business details" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") do
            plain "Shown to customers on checkout pages, payment links and email receipts."
          end
        end

        form(action: settings_merchant_branding_path, method: "post",
             class: "px-6 py-6 flex flex-col gap-5") do
          input(type: "hidden", name: "_method",            value: "patch")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

          # Display name
          div do
            label(class: "block #{TYPE_CAPTION} mb-1.5", for: "display_name") { plain "Display name" }
            input(id: "display_name", type: "text", name: "display_name",
                  value: @branding&.display_name.presence || @merchant&.trading_name.presence || "",
                  placeholder: @merchant&.legal_name.presence || "Your business name",
                  class: form_input_cls)
            p(class: "#{TYPE_CAPTION} mt-1.5") do
              plain "Overrides your registered trading name in customer-facing surfaces."
            end
          end

          # Read-only KYB identity fields
          div(class: "grid grid-cols-2 gap-4") do
            [
              [ "Trading name", @merchant&.trading_name ],
              [ "Legal name",   @merchant&.legal_name ],
              [ "General email", @merchant&.general_email ],
              [ "Support phone", @merchant&.support_phone ]
            ].each do |lbl, val|
              div do
                label(class: "block #{TYPE_CAPTION} mb-1.5") { plain "#{lbl} (from KYB)" }
                div(class: "#{form_input_cls} text-gray-400 bg-gray-50 select-text") { plain val.presence || "—" }
              end
            end
          end

          render UI::Button.new(variant: :primary, type: "submit") { plain "Save changes" }
        end
      end
    end

    def form_input_cls
      "w-full h-9 border border-gray-200 rounded-[9px] px-3 text-[13px] text-gray-700 " \
      "bg-white outline-none focus:ring-1 focus:ring-[#{BRAND}] leading-none flex items-center"
    end
  end
end
