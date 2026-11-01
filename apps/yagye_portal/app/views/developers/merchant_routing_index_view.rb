# frozen_string_literal: true

module Developers
  class MerchantRoutingIndexView < ApplicationComponent
    include UI::Theme

    def initialize(configurations:)
      @configurations = configurations
    end

    def view_template
      render Layout::Shell.new(
        active_nav:  :merchant_routing,
        title:       "My Routing",
        breadcrumbs: [{ label: "My Routing" }]
      ) do
        render UI::PageHeader.new(
          title:    "Payment Routing",
          subtitle: "Configure how payments are distributed across your connected PSP providers."
        ) do
          render UI::Button.new(variant: :primary, href: new_developers_merchant_routing_path) do
            render UI::Icon.new(:plus, class: ICON_SM)
            plain "New configuration"
          end
        end

        info_banner
        configurations_section
      end
    end

    private

    def info_banner
      div(class: "mb-5") do
        render UI::Notice.new(
          variant: :info,
          title:   "Merchant-scoped routing",
          body:    "These configurations control how payments are distributed across your connected " \
                   "PSP providers (Paystack, Flutterwave, etc.). Only one configuration is active at " \
                   "a time — publishing a new one archives the previous. Configurations only affect " \
                   "providers you have connected under PSP Providers."
        )
      end
    end

    def configurations_section
      if @configurations.empty?
        empty_state
      else
        published = @configurations.select { |c| c["state"] == "published" }
        drafts    = @configurations.select { |c| c["state"] == "draft" }
        archived  = @configurations.select { |c| c["state"] == "archived" }

        div(class: "flex flex-col gap-6") do
          active_config_card(published.first) if published.any?
          configurations_table("Drafts",   drafts)   if drafts.any?
          configurations_table("Archived", archived) if archived.any?
        end
      end
    end

    def active_config_card(config)
      div(class: "bg-white border border-green-100 rounded-2xl overflow-hidden") do
        div(class: "flex items-center justify-between px-6 py-4 border-b border-green-100") do
          div(class: "flex items-center gap-3") do
            div(class: "w-2 h-2 rounded-full bg-green-500",
                style: "box-shadow: 0 0 0 3px rgba(22,163,74,0.15)")
            div do
              p(class: "text-[14px] font-bold text-gray-900 leading-tight") { plain config["name"] }
              p(class: "#{TYPE_MICRO} text-gray-400 mt-[1px]") do
                plain "Published #{fmt_published(config["published_at"])}"
              end
            end
          end
          div(class: "flex items-center gap-2") do
            render UI::StatusBadge.new("published")
            render UI::Button.new(variant: :secondary,
                   href: edit_developers_merchant_routing_path(config["id"])) do
              render UI::Icon.new(:edit, class: ICON_SM)
              plain "Edit"
            end
          end
        end
        div(class: "px-6 py-5") do
          p(class: TYPE_CAPTION) do
            plain "Configuration ID: "
            code(class: TYPE_MONO) { plain config["public_id"] }
          end
        end
      end
    end

    def configurations_table(heading, configs)
      div(class: SURFACE_CARD) do
        div(class: "px-5 py-3 border-b border-gray-100") do
          p(class: "text-[12px] font-semibold text-gray-500 uppercase tracking-wide") { plain heading }
        end
        div(class: "overflow-x-auto") do
          table(class: "w-full") do
            thead do
              tr(class: TABLE_HEADER) do
                th(class: TABLE_TH) { plain "Name" }
                th(class: TABLE_TH) { plain "Status" }
                th(class: TABLE_TH) { plain "Last saved" }
                th(class: TABLE_TH)
              end
            end
            tbody do
              configs.each { |c| configuration_row(c) }
            end
          end
        end
      end
    end

    def configuration_row(config)
      tr(class: TABLE_ROW) do
        td(class: TABLE_CELL) do
          p(class: TYPE_BODY_MD) { plain config["name"] }
          p(class: TYPE_CAPTION) { plain config["public_id"] }
        end
        td(class: TABLE_CELL) { render UI::StatusBadge.new(config["state"].presence || "draft") }
        td(class: TABLE_CELL) do
          ts = config["updated_at"] || config["inserted_at"]
          plain ts ? (fmt_date(Time.parse(ts)) rescue "—") : "—"
        end
        td(class: "#{TABLE_CELL} text-right pr-5") do
          div(class: "flex items-center justify-end gap-2") do
            render UI::Button.new(variant: :secondary,
                   href: edit_developers_merchant_routing_path(config["id"])) do
              render UI::Icon.new(:edit, class: ICON_SM)
              plain "Edit"
            end

            if config["state"] == "draft"
              form(action: publish_developers_merchant_routing_path(config["id"]), method: "post",
                   class: "contents") do
                input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                button(type: "submit", class: "#{BTN_PRIMARY}") { plain "Publish" }
              end
            end
          end
        end
      end
    end

    def empty_state
      div(class: "#{SURFACE_CARD} flex flex-col items-center justify-center py-20 gap-4") do
        div(class: "w-14 h-14 rounded-2xl bg-gray-100 flex items-center justify-center") do
          span(class: "flex w-6 h-6 text-gray-400") { render UI::Icon.new(:swap, class: "w-full h-full") }
        end
        div(class: "text-center") do
          p(class: TYPE_TITLE) { plain "No routing configurations yet" }
          p(class: "#{TYPE_CAPTION} mt-1 max-w-[360px]") do
            plain "Create a routing configuration to control how payments flow across your connected PSPs."
          end
        end
        render UI::Button.new(variant: :primary, href: new_developers_merchant_routing_path) do
          render UI::Icon.new(:plus, class: ICON_SM)
          plain "New configuration"
        end
      end
    end

    def fmt_published(ts)
      return "—" unless ts
      Time.parse(ts).strftime("%d %b %Y at %H:%M UTC")
    rescue ArgumentError, TypeError
      "—"
    end
  end
end
