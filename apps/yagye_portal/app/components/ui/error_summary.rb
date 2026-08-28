module UI
  class ErrorSummary < ApplicationComponent
    def initialize(errors:)
      @errors = errors
    end

    def view_template
      return unless @errors.any?

      div class: "mb-5 #{UI::Theme::ERROR_BANNER}" do
        ul class: UI::Theme::ERROR_ITEM do
          @errors.each do |error|
            li { plain error.full_message }
          end
        end
      end
    end
  end
end
