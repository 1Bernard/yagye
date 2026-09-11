# frozen_string_literal: true

module Checkout
  class PaymentLinksIndexView < ApplicationComponent
    include UI::Theme

    def initialize(links:)
      @links = links
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :payment_links,
        title: "Payment Links",
        breadcrumbs: [ { label: "Payment Links" } ]
      ) do
        div(class: "flex items-center justify-between mb-5") do
          p(class: TYPE_BODY) { plain "Create shareable links that take customers straight to checkout." }
          render UI::Button.new(variant: :primary, href: new_payment_link_path) do
            render UI::Icon.new(:plus, class: ICON_SM)
            plain "New link"
          end
        end

        if @links.empty?
          empty_state
        else
          links_table
        end
      end
    end

    private

    def empty_state
      div(class: "#{SURFACE_CARD} flex flex-col items-center justify-center py-20 gap-4") do
        div(class: "w-14 h-14 rounded-2xl bg-gray-100 flex items-center justify-center") do
          span(class: "w-6 h-6 text-gray-400") { render UI::Icon.new(:link, class: "w-full h-full") }
        end
        div(class: "text-center") do
          p(class: TYPE_TITLE) { plain "No payment links yet" }
          p(class: "#{TYPE_CAPTION} mt-1 max-w-xs") do
            plain "Create a link to start accepting payments without any integration."
          end
        end
        render UI::Button.new(variant: :primary, href: new_payment_link_path) do
          render UI::Icon.new(:plus, class: ICON_SM)
          plain "Create payment link"
        end
      end
    end

    def links_table
      div(class: TABLE_CARD) do
        table(class: "w-full") do
          thead do
            tr(class: TABLE_HEADER) do
              th(class: TABLE_TH) { plain "Description" }
              th(class: TABLE_TH) { plain "Amount" }
              th(class: TABLE_TH) { plain "Status" }
              th(class: TABLE_TH) { plain "Uses" }
              th(class: TABLE_TH) { plain "" }
            end
          end
          tbody do
            @links.each { |link| link_row(link) }
          end
        end
      end
    end

    def link_row(link)
      tr(class: TABLE_ROW) do
        td(class: TABLE_CELL) do
          div(class: "flex flex-col gap-0.5") do
            span(class: TYPE_BODY_MD) { plain link["description"] || "—" }
            span(class: TYPE_MONO) { plain link["url_slug"] }
          end
        end
        td(class: "#{TABLE_CELL} #{TYPE_NUM}") do
          if link["amount"]
            plain "#{currency_symbol(link['currency'])}#{format_amount(link['amount'])}"
          else
            span(class: TYPE_CAPTION) { plain "Customer sets amount" }
          end
        end
        td(class: TABLE_CELL) do
          badge = link["active"] ? BADGE_SUCCESS : BADGE_NEUTRAL
          span(class: badge) { plain link["active"] ? "Active" : "Inactive" }
        end
        td(class: "#{TABLE_CELL} #{TYPE_CAPTION}") do
          uses = link["use_count"] || 0
          max  = link["max_uses"]
          plain max ? "#{uses} / #{max}" : uses.to_s
        end
        td(class: TABLE_CELL) do
          div(class: "flex items-center gap-2 justify-end") do
            render UI::Button.new(variant: :secondary, href: payment_link_layout_path(link["id"])) do
              plain "Edit layout"
            end
          end
        end
      end
    end

    def currency_symbol(code)
      { "GHS" => "GH₵", "USD" => "$", "EUR" => "€", "GBP" => "£", "NGN" => "₦" }.fetch(code, code)
    end

    def format_amount(minor_units)
      "%.2f" % (minor_units / 100.0)
    end
  end
end
