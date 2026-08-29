module UI
  class StatCard < ApplicationComponent
    def initialize(label:, value:, icon: nil, change: nil)
      @label  = label
      @value  = value
      @icon   = icon
      @change = change
    end

    def view_template
      div class: "#{UI::Theme::CARD} flex items-center gap-4 px-5 py-4" do
        if @icon
          div class: "w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0 #{UI::Theme::ICON_BG_TEAL}" do
            svg @icon
          end
        end
        div do
          p class: "text-xs mb-0.5 #{UI::Theme::MUTED}" do
            plain @label
          end
          p class: "text-xl font-semibold tabular-nums #{UI::Theme::HEADING}" do
            plain @value
          end
          if @change
            p class: "text-xs mt-0.5 #{UI::Theme::MUTED}" do
              plain @change
            end
          end
        end
      end
    end
  end
end
