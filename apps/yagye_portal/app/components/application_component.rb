# frozen_string_literal: true

class ApplicationComponent < Phlex::HTML
  include Phlex::Rails::Helpers::Routes
  include Phlex::Rails::Helpers::ContentFor

  register_value_helper :policy
  register_value_helper :policy_scope
  register_value_helper :flash
  register_value_helper :params
  register_value_helper :request
  register_value_helper :current_user
  register_value_helper :form_authenticity_token
  register_value_helper :number_to_currency
  register_value_helper :number_with_delimiter
  register_value_helper :translate
  register_value_helper :asset_path
  register_value_helper :l

  register_element :turbo_frame

  def can?(query, record) = policy(record).public_send(query)

  def t(key, **)
    key = "#{i18n_scope}#{key}" if key.to_s.start_with?(".")
    translate(key, **)
  end

  def turbo_frame_tag(id, src: nil, **attrs, &)
    attrs[:src] = src if src
    turbo_frame(id: id, **attrs, &)
  end

  def cache_store = Rails.cache

  private

  def vanish(&block)
    return unless block
    capture { block.call(self) }
    nil
  end

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
    @i18n_scope ||= self.class.name.delete_suffix("View").underscore.tr("/", ".")
  end
end
