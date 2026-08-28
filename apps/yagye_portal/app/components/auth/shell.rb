module Auth
  class Shell < ApplicationComponent
    def initialize(title:, subtitle: nil)
      @title    = title
      @subtitle = subtitle
    end

    def view_template
      div class: "min-h-screen bg-gray-50 flex flex-col items-center justify-center px-4 py-12" do
        div class: "flex items-center gap-2 mb-8" do
          div class: "w-9 h-9 rounded-full flex items-center justify-center #{UI::Theme::LOGO_ICON}" do
            span class: "text-sm font-bold" do
              plain "Y"
            end
          end
          span class: "text-lg font-semibold #{UI::Theme::HEADING}" do
            plain "Yagye"
          end
        end

        div class: "#{UI::Theme::CARD} w-full max-w-sm px-8 py-10" do
          div class: "mb-6 text-center" do
            h1 class: "text-xl font-semibold text-gray-900 mb-1" do
              plain @title
            end
            if @subtitle
              p class: "text-sm text-gray-500 mt-1" do
                plain @subtitle
              end
            end
          end
          yield
        end

        p class: "mt-6 text-xs text-gray-400 text-center" do
          plain "© #{Time.current.year} Yagye · "
          a href: "#", class: "hover:text-gray-600 transition-colors" do
            plain "Privacy"
          end
          plain " · "
          a href: "#", class: "hover:text-gray-600 transition-colors" do
            plain "Terms"
          end
        end
      end
    end
  end
end
