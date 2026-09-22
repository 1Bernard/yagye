# frozen_string_literal: true

module UI
  class Notice < ApplicationComponent
    include UI::Theme

    VARIANTS = {
      info:    { icon: :info_circle,  palette: "brand", bg: "rgba(61,71,245,0.05)",  border: "rgba(61,71,245,0.15)", accent: "#3D47F5" },
      warning: { icon: :alert_circle, palette: "amber", bg: "rgba(217,119,6,0.06)",  border: "rgba(217,119,6,0.22)", accent: "#d97706" },
      caution: { icon: :info_circle,  palette: "amber", bg: "#fffbeb",               border: "#fde68a",              accent: "#b45309" },
      error:   { icon: :alert_circle, palette: "red",   bg: "rgba(220,38,38,0.05)",  border: "rgba(220,38,38,0.18)", accent: "#dc2626" },
      success: { icon: :check_circle, palette: "green", bg: "rgba(22,163,74,0.05)",  border: "rgba(22,163,74,0.18)", accent: "#16a34a" }
    }.freeze

    SIZES = {
      sm: { padding: "px-3 py-2.5",  badge: "w-6 h-6 rounded-md", icon: "w-[11px] h-[11px]", title: "text-[12px]",   body: "text-[11px]"   },
      md: { padding: "px-4 py-3",    badge: "w-7 h-7 rounded-lg", icon: "w-[13px] h-[13px]", title: "text-[12.5px]", body: "text-[11.5px]" },
      lg: { padding: "px-5 py-4",    badge: "w-8 h-8 rounded-xl", icon: "w-[15px] h-[15px]", title: "text-[13px]",   body: "text-[12px]"   },
    }.freeze

    def initialize(title:, body: nil, variant: :info, size: :md, icon: nil, dismissable: false, action_label: nil, action_href: nil)
      @title        = title
      @body         = body
      @variant      = VARIANTS.fetch(variant.to_sym, VARIANTS[:info])
      @size         = SIZES.fetch(size.to_sym, SIZES[:md])
      @icon         = icon || @variant[:icon]
      @dismissable  = dismissable
      @action_label = action_label
      @action_href  = action_href
    end

    def view_template
      root_attrs = {
        class: "flex items-start gap-3 rounded-xl #{@size[:padding]}",
        style: "background:#{@variant[:bg]};border:1px solid #{@variant[:border]};"
      }
      root_attrs[:data] = { controller: "notice" } if @dismissable

      div(**root_attrs) do
        div(class: "#{@size[:badge]} icon-#{@variant[:palette]} flex items-center justify-center flex-shrink-0 mt-px") do
          span(class: "flex #{@size[:icon]}") { render UI::Icon.new(@icon, class: "w-full h-full") }
        end

        div(class: "flex-1 min-w-0") do
          p(class: "#{@size[:title]} font-semibold leading-tight", style: "color:var(--ink)") { plain @title }
          if @body
            p(class: "#{@size[:body]} leading-[1.5] mt-[2px]", style: "color:var(--muted-text)") { plain @body }
          elsif block_given?
            yield
          end
        end

        if @action_href
          a(href: @action_href,
            class: "flex-shrink-0 self-center text-[12px] font-semibold no-underline whitespace-nowrap",
            style: "color:#{@variant[:accent]}") { plain @action_label }
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
