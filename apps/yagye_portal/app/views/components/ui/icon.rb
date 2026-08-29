# frozen_string_literal: true

module UI
  # All SVG icon geometry lives here — one place, structured Phlex calls.
  # Components never embed raw SVG path data; they render UI::Icon.new(:name).
  class Icon < ApplicationComponent
    ICONS = %i[
      eye eye_off spinner arrow_right arrow_left
      mail lock unlock shield check x plus dots dots_vertical chev chev_up chev_left chev_right
      search filter calendar clock
      users user settings logout edit archive file help
      bell chart bar_chart line_chart download upload copy pin globe
      swap refresh phone wallet credit_card bank building
      alert_circle info_circle check_circle
      home flag key grid magnet headset trending_up trending_down
      external_link link layers tag hash
    ].freeze

    def initialize(name, **attrs)
      @name  = name.to_sym
      @attrs = attrs
    end

    # Build raw SVG string so ApplicationComponent#svg(content) (a raw-string
    # helper) never interferes with element rendering.
    def view_template
      raise ArgumentError, "Unknown icon :#{@name}" unless ICONS.include?(@name)

      b = SvgBuilder.new
      send(@name, b)

      root = build_root_attrs
      attr_str = root.map { |k, v| %(#{k}="#{v}") }.join(" ")
      raw safe(%(<svg #{attr_str}>#{b.content}</svg>))
    end

    private

    def build_root_attrs
      base = {
        "viewBox"         => "0 0 24 24",
        "fill"            => "none",
        "stroke"          => "currentColor",
        "stroke-width"    => "1.8",
        "stroke-linecap"  => "round",
        "stroke-linejoin" => "round"
      }
      @attrs.each_with_object(base) do |(k, v), h|
        h[svg_attr_name(k.to_s)] = v
      end
    end

    def svg_attr_name(str)
      return "viewBox" if str.downcase == "viewbox"
      str.tr("_", "-")
    end

    # Accumulates SVG inner-element strings.
    # Attribute names are converted: stroke_width → stroke-width.
    class SvgBuilder
      attr_reader :content

      def initialize
        @content = +""
      end

      %i[path circle line polyline rect polygon ellipse].each do |tag_name|
        define_method(tag_name) do |**attrs|
          attr_str = attrs.map { |k, v| %(#{k.to_s.tr("_", "-")}="#{v}") }.join(" ")
          @content << "<#{tag_name} #{attr_str}/>"
        end
      end
    end

    def eye(s)
      s.path(d: "M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z")
      s.circle(cx: "12", cy: "12", r: "3")
    end

    def eye_off(s)
      s.path(d: "M3 3l18 18M10.5 6A9.8 9.8 0 0 1 12 5.5C18 5.5 21.5 12 21.5 12a17 17 0 0 1-2.6 3.3M6.6 6.6C4 8.6 2.5 12 2.5 12S6 18.5 12 18.5c1.3 0 2.5-.3 3.5-.8")
      s.path(d: "M9.9 9.9a3 3 0 0 0 4.2 4.2")
    end

    def spinner(s)
      s.circle(cx: "12", cy: "12", r: "10", stroke_width: "4", class: "opacity-25")
      s.path(d: "M22 12a10 10 0 0 0-10-10", stroke_width: "4")
    end

    def arrow_right(s)
      s.path(d: "M5 12h14")
      s.path(d: "m12 5 7 7-7 7")
    end

    def arrow_left(s)
      s.path(d: "M19 12H5")
      s.path(d: "m12 19-7-7 7-7")
    end

    def mail(s)
      s.rect(width: "20", height: "16", x: "2", y: "4", rx: "2")
      s.path(d: "m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7")
    end

    def lock(s)
      s.rect(width: "18", height: "11", x: "3", y: "11", rx: "2")
      s.path(d: "M7 11V7a5 5 0 0 1 10 0v4")
    end

    def unlock(s)
      s.rect(width: "18", height: "11", x: "3", y: "11", rx: "2")
      s.path(d: "M7 11V7a5 5 0 0 1 9.9-1")
    end

    def shield(s)
      s.path(d: "M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z")
    end

    def check(s)
      s.path(d: "M20 6 9 17l-5-5")
    end

    def x(s)
      s.path(d: "M18 6 6 18")
      s.path(d: "m6 6 12 12")
    end

    def plus(s)
      s.path(d: "M5 12h14")
      s.path(d: "M12 5v14")
    end

    def dots(s)
      s.circle(cx: "12", cy: "12", r: "1")
      s.circle(cx: "19", cy: "12", r: "1")
      s.circle(cx: "5", cy: "12", r: "1")
    end

    def chev(s)
      s.path(d: "m6 9 6 6 6-6")
    end

    def chev_up(s)
      s.path(d: "m18 15-6-6-6 6")
    end

    def search(s)
      s.circle(cx: "11", cy: "11", r: "8")
      s.path(d: "m21 21-4.3-4.3")
    end

    def filter(s)
      s.line(x1: "21", x2: "14", y1: "4", y2: "4")
      s.line(x1: "10", x2: "3", y1: "4", y2: "4")
      s.line(x1: "21", x2: "12", y1: "12", y2: "12")
      s.line(x1: "8", x2: "3", y1: "12", y2: "12")
      s.line(x1: "21", x2: "16", y1: "20", y2: "20")
      s.line(x1: "12", x2: "3", y1: "20", y2: "20")
      s.line(x1: "14", x2: "14", y1: "2", y2: "6")
      s.line(x1: "8", x2: "8", y1: "10", y2: "14")
      s.line(x1: "16", x2: "16", y1: "18", y2: "22")
    end

    def calendar(s)
      s.path(d: "M8 2v4")
      s.path(d: "M16 2v4")
      s.rect(width: "18", height: "18", x: "3", y: "4", rx: "2")
      s.path(d: "M3 10h18")
    end

    def clock(s)
      s.circle(cx: "12", cy: "12", r: "10")
      s.path(d: "M12 6v6l4 2")
    end

    def users(s)
      s.path(d: "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2")
      s.circle(cx: "9", cy: "7", r: "4")
      s.path(d: "M22 21v-2a4 4 0 0 0-3-3.87")
      s.path(d: "M16 3.13a4 4 0 0 1 0 7.75")
    end

    def user(s)
      s.path(d: "M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2")
      s.circle(cx: "12", cy: "7", r: "4")
    end

    def settings(s)
      s.circle(cx: "12", cy: "12", r: "3")
      s.path(d: "M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z")
    end

    def logout(s)
      s.path(d: "M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4")
      s.polyline(points: "16 17 21 12 16 7")
      s.line(x1: "21", x2: "9", y1: "12", y2: "12")
    end

    def edit(s)
      s.path(d: "M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z")
    end

    def archive(s)
      s.rect(width: "20", height: "5", x: "2", y: "3", rx: "1")
      s.path(d: "M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8")
      s.path(d: "M10 12h4")
    end

    def file(s)
      s.path(d: "M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z")
      s.path(d: "M14 2v4a2 2 0 0 0 2 2h4")
    end

    def help(s)
      s.circle(cx: "12", cy: "12", r: "10")
      s.path(d: "M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3")
      s.path(d: "M12 17h.01")
    end

    def bell(s)
      s.path(d: "M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9")
      s.path(d: "M10.3 21a1.94 1.94 0 0 0 3.4 0")
    end

    def chart(s)
      s.line(x1: "12", x2: "12", y1: "20", y2: "10")
      s.line(x1: "18", x2: "18", y1: "20", y2: "4")
      s.line(x1: "6", x2: "6", y1: "20", y2: "16")
    end

    def bar_chart(s)
      s.rect(width: "6", height: "9", x: "3", y: "12", rx: "1")
      s.rect(width: "6", height: "14", x: "9", y: "7", rx: "1")
      s.rect(width: "6", height: "18", x: "15", y: "3", rx: "1")
      s.path(d: "M3 22h18")
    end

    def download(s)
      s.path(d: "M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3")
    end

    def upload(s)
      s.path(d: "M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5m-13.5-9L12 3m0 0 4.5 4.5M12 3v13.5")
    end

    def copy(s)
      s.rect(width: "13", height: "13", x: "9", y: "9", rx: "2")
      s.path(d: "M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1")
    end

    def pin(s)
      s.path(d: "M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z")
      s.circle(cx: "12", cy: "10", r: "3")
    end

    def globe(s)
      s.circle(cx: "12", cy: "12", r: "10")
      s.path(d: "M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20")
      s.path(d: "M2 12h20")
    end

    def swap(s)
      s.path(d: "m17 4 4 4-4 4")
      s.path(d: "M3 8h18")
      s.path(d: "m7 20-4-4 4-4")
      s.path(d: "M21 16H3")
    end

    def refresh(s)
      s.path(d: "M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8")
      s.path(d: "M21 3v5h-5")
      s.path(d: "M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16")
      s.path(d: "M8 16H3v5")
    end

    def phone(s)
      s.path(d: "M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z")
    end

    def wallet(s)
      s.path(d: "M20 12V8H6a2 2 0 0 1-2-2c0-1.1.9-2 2-2h12v4")
      s.path(d: "M4 6v12c0 1.1.9 2 2 2h14v-4")
      s.path(d: "M18 12a2 2 0 0 0 0 4h4v-4Z")
    end

    def credit_card(s)
      s.rect(width: "20", height: "14", x: "2", y: "5", rx: "2")
      s.line(x1: "2", x2: "22", y1: "10", y2: "10")
    end

    def bank(s)
      s.line(x1: "3", x2: "21", y1: "22", y2: "22")
      %w[6 10 14 18].each { |x| s.line(x1: x, x2: x, y1: "18", y2: "11") }
      s.polygon(points: "12 2 20 7 4 7")
    end

    def alert_circle(s)
      s.circle(cx: "12", cy: "12", r: "10")
      s.line(x1: "12", x2: "12", y1: "8", y2: "12")
      s.line(x1: "12", x2: "12.01", y1: "16", y2: "16")
    end

    def info_circle(s)
      s.circle(cx: "12", cy: "12", r: "10")
      s.path(d: "M12 16v-4")
      s.path(d: "M12 8h.01")
    end

    def check_circle(s)
      s.path(d: "M22 11.08V12a10 10 0 1 1-5.93-9.14")
      s.path(d: "m9 11 3 3L22 4")
    end

    def dots_vertical(s)
      s.circle(cx: "12", cy: "5", r: "1")
      s.circle(cx: "12", cy: "12", r: "1")
      s.circle(cx: "12", cy: "19", r: "1")
    end

    def chev_left(s)
      s.path(d: "m15 18-6-6 6-6")
    end

    def chev_right(s)
      s.path(d: "m9 18 6-6-6-6")
    end

    def line_chart(s)
      s.path(d: "M3 3v18h18")
      s.path(d: "m19 9-5 5-4-4-3 3")
    end

    def home(s)
      s.path(d: "m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z")
      s.polyline(points: "9 22 9 12 15 12 15 22")
    end

    def flag(s)
      s.path(d: "M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z")
      s.line(x1: "4", x2: "4", y1: "22", y2: "15")
    end

    def key(s)
      s.circle(cx: "7.5", cy: "15.5", r: "5.5")
      s.path(d: "m21 2-9.6 9.6")
      s.path(d: "m15.5 7.5 3 3L22 7l-3-3")
    end

    def grid(s)
      s.rect(width: "7", height: "7", x: "3", y: "3", rx: "1")
      s.rect(width: "7", height: "7", x: "14", y: "3", rx: "1")
      s.rect(width: "7", height: "7", x: "14", y: "14", rx: "1")
      s.rect(width: "7", height: "7", x: "3", y: "14", rx: "1")
    end

    def building(s)
      s.rect(width: "16", height: "20", x: "4", y: "2", rx: "2")
      s.path(d: "M9 22v-4h6v4")
      s.path(d: "M8 6h.01")
      s.path(d: "M16 6h.01")
      s.path(d: "M12 6h.01")
      s.path(d: "M12 10h.01")
      s.path(d: "M12 14h.01")
      s.path(d: "M16 10h.01")
      s.path(d: "M16 14h.01")
      s.path(d: "M8 10h.01")
      s.path(d: "M8 14h.01")
    end

    def magnet(s)
      s.path(d: "M6 15A6 6 0 0 0 18 15")
      s.path(d: "M6 15V5a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v10")
      s.line(x1: "2", x2: "6", y1: "15", y2: "15")
      s.line(x1: "18", x2: "22", y1: "15", y2: "15")
    end

    def headset(s)
      s.path(d: "M3 11h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-5Zm0 0a9 9 0 1 1 18 0m0 0v5a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3Z")
      s.path(d: "M21 16v2a4 4 0 0 1-4 4h-5")
    end

    def trending_up(s)
      s.polyline(points: "22 7 13.5 15.5 8.5 10.5 2 17")
      s.polyline(points: "16 7 22 7 22 13")
    end

    def trending_down(s)
      s.polyline(points: "22 17 13.5 8.5 8.5 13.5 2 7")
      s.polyline(points: "16 17 22 17 22 11")
    end

    def external_link(s)
      s.path(d: "M15 3h6v6")
      s.path(d: "M10 14 21 3")
      s.path(d: "M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6")
    end

    def link(s)
      s.path(d: "M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71")
      s.path(d: "M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71")
    end

    def layers(s)
      s.path(d: "m12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z")
      s.path(d: "m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65")
      s.path(d: "m22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65")
    end

    def tag(s)
      s.path(d: "M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42z")
      s.circle(cx: "7.5", cy: "7.5", r: ".5", fill: "currentColor")
    end

    def hash(s)
      s.line(x1: "4", x2: "20", y1: "9", y2: "9")
      s.line(x1: "4", x2: "20", y1: "15", y2: "15")
      s.line(x1: "10", x2: "8", y1: "3", y2: "21")
      s.line(x1: "16", x2: "14", y1: "3", y2: "21")
    end
  end
end
