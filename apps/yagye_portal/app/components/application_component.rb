# frozen_string_literal: true

class ApplicationComponent < Phlex::HTML
  include Phlex::Rails::Helpers::Routes
  include Phlex::Rails::Helpers::Translate
  include Phlex::Rails::Helpers::T
  include Phlex::Rails::Helpers::LinkTo
  include Phlex::Rails::Helpers::ContentFor
  include Phlex::Rails::Helpers::TurboFrameTag
  include Phlex::Rails::Helpers::TurboStreamFrom
  include Pundit::Authorization

  # Auto-scoped i18n: ".key" resolves relative to the component's namespace.
  # Auth::SignInPage -> "auth.sign_in_page.key"
  def t(key, **)
    if key.to_s.start_with?(".")
      helpers.translate("#{i18n_scope}#{key}", **)
    else
      helpers.translate(key, **)
    end
  end

  register_element :turbo_frame

  private

  def can?(action, subject)
    policy = Pundit.policy(Current.user, subject)
    policy.public_send(:"#{action}?")
  rescue Pundit::NotDefinedError
    false
  end

  # Runs the block to collect slot definitions (columns, field defs, etc.)
  # without emitting any HTML output — side effects (instance var writes)
  # survive, rendered output does not.
  def vanish(&block)
    return unless block
    capture { block.call(self) }
    nil
  end

  # Embed a trusted SVG string. Use only with literals — never user input.
  def svg(content)
    raw safe(content.to_s)
  end

  def stat_cell(label, value, color: UI::Theme::INK)
    div(class: UI::Theme::STAT_CELL) do
      p(style: UI::Theme::TYPE_MICRO) { label }
      p(style: "font-size:28px;font-weight:700;color:#{color};" \
                "font-variant-numeric:tabular-nums;line-height:1;margin-top:6px") { value }
    end
  end

  def i18n_scope
    @i18n_scope ||= self.class.name.underscore.tr("/", ".")
  end
end
