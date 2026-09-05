# frozen_string_literal: true

module Forms
  # Shared foundation for every form in the portal.
  #
  # Superform::Rails::Form auto-detects ApplicationComponent by constant
  # name, so every subclass inherits Routes/helpers for free.
  class Base < Superform::Rails::Form
  end
end
