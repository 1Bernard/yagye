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
    tint_bg = tint || UI::Theme::TINT_GRAY

    div(class: "bg-white border border-gray-100 rounded-2xl p-[22px]") do
      if icon
        div(class: "flex items-start justify-between mb-[14px]") do
          div(class: "w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0",
              style: "background:#{tint_bg}") do
            span(class: "flex w-[17px] h-[17px]", style: "color:#{color}") do
              render UI::Icon.new(icon, class: "w-full h-full")
            end
          end
          if delta
            positive = delta.to_f >= 0
            dc = positive ? UI::Theme::GREEN : UI::Theme::RED
            db = positive ? UI::Theme::TINT_GREEN : UI::Theme::TINT_RED
            span(class: "text-[11px] font-semibold px-[7px] py-[2px] rounded-full",
                 style: "color:#{dc};background:#{db}") do
              plain "#{positive ? '+' : ''}#{delta}%"
            end
          end
        end
      end
      p(class: "#{UI::Theme::TYPE_HEADING} mb-2") { plain label }
      p(class: "#{UI::Theme::TYPE_STAT} mt-2", style: "color:#{color}") { plain value }
    end
  end

  def meta_cell(label, value, mono: false)
    div(class: "bg-white px-[18px] py-[14px]") do
      p(class: "#{UI::Theme::TYPE_MICRO} mb-1") { plain label }
      p(class: mono ? UI::Theme::TYPE_MONO : UI::Theme::TYPE_BODY_MD) { plain value.to_s }
    end
  end

  def timeline_item(label, timestamp, color, last: false)
    div(class: "flex gap-[14px]") do
      div(class: "flex flex-col items-center flex-shrink-0") do
        div(class: "w-[10px] h-[10px] rounded-full flex-shrink-0 mt-[3px]", style: "background:#{color}")
        div(class: "w-[1px] flex-1 bg-gray-100 mt-1") unless last
      end
      div(class: last ? "" : "pb-4") do
        p(class: UI::Theme::TYPE_BODY_MD) { plain label }
        p(class: UI::Theme::TYPE_CAPTION) { plain timestamp&.strftime("%d %b %Y, %H:%M") || "—" }
      end
    end
  end

  def format_ghs(cents)
    n = cents.to_f / 100
    whole, frac = sprintf("%.2f", n).split(".")
    "GHS #{whole.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}.#{frac}"
  end

  def i18n_scope
    @i18n_scope ||= self.class.name.delete_suffix("View").underscore.tr("/", ".")
  end
end
