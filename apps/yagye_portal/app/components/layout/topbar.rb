module Layout
  class Topbar < ApplicationComponent
    def initialize(title:, subtitle: nil)
      @title    = title
      @subtitle = subtitle
    end

    def view_template
      header class: "#{UI::Theme::TOPBAR} flex items-center justify-between px-6 py-4 sticky top-0 z-10" do
        title_block
        div class: "flex items-center gap-3" do
          search_box
          action_icons
          user_menu
        end
      end
    end

    private

    def title_block
      div do
        h1 class: UI::Theme::PAGE_TITLE do
          plain @title
        end
        if @subtitle
          p class: UI::Theme::PAGE_SUBTITLE do
            plain @subtitle
          end
        end
      end
    end

    def search_box
      div class: "relative" do
        span class: "absolute inset-y-0 left-3 flex items-center pointer-events-none #{UI::Theme::NAV_ICON_OFF}" do
          svg search_icon
        end
        input(
          type: "text",
          placeholder: "Search...",
          class: "#{UI::Theme::SEARCH_INPUT} pl-9 pr-14 py-1.5 w-56"
        )
        span class: "absolute inset-y-0 right-3 flex items-center text-xs pointer-events-none #{UI::Theme::NAV_ICON_OFF}" do
          plain "⌘K"
        end
      end
    end

    def action_icons
      div class: "flex items-center gap-1" do
        %i[info settings mail bell].each do |name|
          button class: "p-1.5 #{UI::Theme::ICON_BUTTON}" do
            svg icon_svg(name)
          end
        end
      end
    end

    def user_menu
      button class: "flex items-center gap-2 pl-3 border-l border-gray-100" do
        div class: "w-8 h-8 rounded-full flex items-center justify-center text-xs font-semibold #{UI::Theme::AVATAR}" do
          plain user_initials
        end
        span class: "text-sm font-medium #{UI::Theme::BODY}" do
          plain Current.user&.full_name || "Account"
        end
        span class: UI::Theme::NAV_ICON_OFF do
          svg chevron_down
        end
      end
    end

    def user_initials
      name = Current.user&.full_name || ""
      name.split.map { |w| w[0] }.first(2).join.upcase
    end

    def search_icon
      %(<svg class="w-4 h-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clip-rule="evenodd"/></svg>)
    end

    def chevron_down
      %(<svg class="w-4 h-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clip-rule="evenodd"/></svg>)
    end

    def icon_svg(name)
      case name
      when :info
        %(<svg class="w-5 h-5" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/></svg>)
      when :settings
        %(<svg class="w-5 h-5" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clip-rule="evenodd"/></svg>)
      when :mail
        %(<svg class="w-5 h-5" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path d="M2.003 5.884L10 9.882l7.997-3.998A2 2 0 0016 4H4a2 2 0 00-1.997 1.884z"/><path d="M18 8.118l-8 4-8-4V14a2 2 0 002 2h12a2 2 0 002-2V8.118z"/></svg>)
      when :bell
        %(<svg class="w-5 h-5" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path d="M10 2a6 6 0 00-6 6v3.586l-.707.707A1 1 0 004 14h12a1 1 0 00.707-1.707L16 11.586V8a6 6 0 00-6-6zM10 18a3 3 0 01-2.83-2h5.66A3 3 0 0110 18z"/></svg>)
      end
    end
  end
end
