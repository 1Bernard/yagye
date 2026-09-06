# frozen_string_literal: true

module UI
  class Notice < ApplicationComponent
    include UI::Theme

    VARIANTS = {
      info:    { icon: :info_circle,  palette: "brand", bg: "rgba(61,71,245,0.05)",  border: "rgba(61,71,245,0.15)"  },
      warning: { icon: :shield,       palette: "amber", bg: "rgba(217,119,6,0.06)",  border: "rgba(217,119,6,0.22)"  },
      error:   { icon: :alert_circle, palette: "red",   bg: "rgba(220,38,38,0.05)",  border: "rgba(220,38,38,0.18)"  },
      success: { icon: :check_circle, palette: "green", bg: "rgba(22,163,74,0.05)",  border: "rgba(22,163,74,0.18)"  }
    }.freeze

    def initialize(title:, body: nil, variant: :info, dismissable: false)
      @title       = title
      @body        = body
      @variant     = VARIANTS.fetch(variant.to_sym, VARIANTS[:info])
      @dismissable = dismissable
    end

    def view_template
      root_attrs = {
        class: "flex items-start gap-3 rounded-xl px-4 py-3",
        style: "background:#{@variant[:bg]};border:1px solid #{@variant[:border]};"
      }
      root_attrs[:data] = { controller: "notice" } if @dismissable

      div(**root_attrs) do
        div(class: "w-7 h-7 rounded-lg icon-#{@variant[:palette]} flex items-center justify-center flex-shrink-0 mt-px") do
          span(class: "flex w-[13px] h-[13px]") { render UI::Icon.new(@variant[:icon], class: "w-full h-full") }
        end

        div(class: "flex-1 min-w-0") do
          p(class: "text-[12.5px] font-semibold leading-tight", style: "color:var(--ink)") { plain @title }
          if @body
            p(class: "text-[11.5px] leading-[1.5] mt-[2px]", style: "color:var(--muted-text)") { plain @body }
          else
            yield
          end
        end

        if @dismissable
          button(type: "button",
                 class: "flex-shrink-0 flex w-6 h-6 items-center justify-center rounded-lg " \
                        "transition-colors hover:bg-black/5",
                 style: "color:var(--muted-text)",
                 aria: { label: "Dismiss" },
                 data: { action: "click->notice#dismiss" }) do
            span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(:x, class: "w-full h-full") }
          end
        end
      end
    end
  end
end
