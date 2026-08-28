module Layout
  class Sidebar < ApplicationComponent
    NAV_SECTIONS = [
      {
        label: "MAIN MENU",
        items: [
          { key: :dashboard,  icon: :home,         label: "Dashboard", path: :authenticated_root_path },
          { key: :payments,   icon: :credit_card,  label: "Payments",  path: :payments_path },
          { key: :disputes,   icon: :flag,         label: "Disputes",  path: :disputes_path }
        ]
      },
      {
        label: "OPERATIONS",
        internal_only: true,
        items: [
          { key: :merchants,   icon: :building,     label: "Merchants",  path: :merchants_path },
          { key: :kyb_reviews, icon: :shield_check, label: "KYB Review", path: :kyb_reviews_path }
        ]
      },
      {
        label: "ACCOUNT",
        items: [
          { key: :api_keys, icon: :key,      label: "API Keys",    path: :api_keys_path },
          { key: :settings, icon: :settings, label: "Settings",    path: :settings_path },
          { key: :help,     icon: :help,     label: "Help & Support", path: :help_path }
        ]
      }
    ].freeze

    def initialize(active:)
      @active = active
    end

    def view_template
      nav class: "#{UI::Theme::SIDEBAR} flex flex-col w-[220px] min-h-screen flex-shrink-0" do
        logo_block
        div class: "flex-1 overflow-y-auto py-4" do
          NAV_SECTIONS.each { |s| nav_section(s) }
        end
      end
    end

    private

    def logo_block
      div class: "flex items-center gap-2 px-5 py-5 border-b border-gray-100" do
        div class: "w-8 h-8 rounded-full flex items-center justify-center #{UI::Theme::LOGO_ICON}" do
          span class: "text-xs font-bold" do
            plain "Y"
          end
        end
        span class: "font-semibold text-base #{UI::Theme::HEADING}" do
          plain "Yagye"
        end
      end
    end

    def nav_section(section)
      return if section[:internal_only] && !internal_staff?

      div class: "px-3 mb-4" do
        p class: "#{UI::Theme::LABEL} px-2 mb-2" do
          plain section[:label]
        end
        section[:items].each { |item| nav_item(item) }
      end
    end

    def nav_item(item)
      active = @active == item[:key]
      path   = send(item[:path]) rescue "#"

      a href: path,
        class: [
          "flex items-center gap-3 px-3 py-2 rounded-lg text-sm mb-0.5 transition-colors",
          active ? UI::Theme::PRIMARY_ACTIVE : UI::Theme::NAV_ITEM
        ].join(" ") do
        nav_icon(item[:icon], active: active)
        span { plain item[:label] }
      end
    end

    def nav_icon(name, active:)
      span class: "w-4 h-4 flex-shrink-0 #{active ? UI::Theme::NAV_ICON_ON : UI::Theme::NAV_ICON_OFF}" do
        svg icon_svg(name)
      end
    end

    def icon_svg(name)
      case name
      when :home
        %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path d="M10.707 2.293a1 1 0 00-1.414 0l-7 7a1 1 0 001.414 1.414L4 10.414V17a1 1 0 001 1h3a1 1 0 001-1v-2a1 1 0 011-1h2a1 1 0 011 1v2a1 1 0 001 1h3a1 1 0 001-1v-6.586l.293.293a1 1 0 001.414-1.414l-7-7z"/></svg>)
      when :credit_card
        %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path d="M4 4a2 2 0 00-2 2v1h16V6a2 2 0 00-2-2H4z"/><path fill-rule="evenodd" d="M18 9H2v5a2 2 0 002 2h12a2 2 0 002-2V9zM4 13a1 1 0 011-1h1a1 1 0 110 2H5a1 1 0 01-1-1zm5-1a1 1 0 100 2h1a1 1 0 100-2H9z" clip-rule="evenodd"/></svg>)
      when :flag
        %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M3 6a3 3 0 013-3h10a1 1 0 01.8 1.6L14.25 8l2.55 3.4A1 1 0 0116 13H6a1 1 0 00-1 1v3a1 1 0 11-2 0V6z" clip-rule="evenodd"/></svg>)
      when :building
        %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M4 4a2 2 0 012-2h8a2 2 0 012 2v12a1 1 0 01-1 1h-2a1 1 0 01-1-1v-2a1 1 0 00-1-1H9a1 1 0 00-1 1v2a1 1 0 01-1 1H5a1 1 0 01-1-1V4zm3 1h2v2H7V5zm2 4H7v2h2V9zm2-4h2v2h-2V5zm2 4h-2v2h2V9z" clip-rule="evenodd"/></svg>)
      when :shield_check
        %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M2.166 4.999A11.954 11.954 0 0010 1.944 11.954 11.954 0 0017.834 5c.11.65.166 1.32.166 2.001 0 5.225-3.34 9.67-8 11.317C5.34 16.67 2 12.225 2 7c0-.682.057-1.35.166-2.001zm11.541 3.708a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/></svg>)
      when :key
        %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M18 8a6 6 0 01-7.743 5.743L10 14l-1 1-1 1H6v2H2v-4l4.257-4.257A6 6 0 1118 8zm-6-4a1 1 0 100 2 2 2 0 012 2 1 1 0 102 0 4 4 0 00-4-4z" clip-rule="evenodd"/></svg>)
      when :settings
        %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clip-rule="evenodd"/></svg>)
      when :help
        %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-8-3a1 1 0 00-.867.5 1 1 0 11-1.731-1A3 3 0 0113 8a3.001 3.001 0 01-2 2.83V11a1 1 0 11-2 0v-1a1 1 0 011-1 1 1 0 100-2zm0 8a1 1 0 100-2 1 1 0 000 2z" clip-rule="evenodd"/></svg>)
      end
    end

    def internal_staff?
      Current.user&.internal_staff?
    rescue
      false
    end
  end
end
