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

  def stat_cell(label, value, color: UI::Theme::INK, icon: nil, tint: nil, delta: nil)
    tint_bg = tint || "rgba(107,114,128,0.08)"

    div(style: "background:#fff;border:1px solid #{UI::Theme::BORDER};border-radius:16px;padding:20px 22px") do
      if icon
        div(style: "display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:14px") do
          div(style: "width:36px;height:36px;border-radius:10px;background:#{tint_bg};" \
                     "display:flex;align-items:center;justify-content:center;flex-shrink:0") do
            span(style: "color:#{color};display:flex;width:17px;height:17px") do
              render UI::Icon.new(icon, class: "w-full h-full")
            end
          end
          if delta
            positive = delta.to_f >= 0
            dc = positive ? "#16a34a" : "#dc2626"
            db = positive ? "rgba(22,163,74,0.08)" : "rgba(220,38,38,0.08)"
            span(style: "font-size:11px;font-weight:600;color:#{dc};" \
                        "padding:2px 7px;border-radius:20px;background:#{db}") do
              "#{positive ? '+' : ''}#{delta}%"
            end
          end
        end
      end
      p(style: UI::Theme::TYPE_HEADING) { label }
      p(style: "font-size:26px;font-weight:700;letter-spacing:-0.03em;color:#{color};" \
               "font-variant-numeric:tabular-nums;line-height:1;margin-top:8px") { value }
    end
  end

  def i18n_scope
    @i18n_scope ||= self.class.name.underscore.tr("/", ".")
  end
end
