module Auth
  class Shell < ApplicationComponent
    def initialize(title:, subtitle: nil)
      @title    = title
      @subtitle = subtitle
    end

    def view_template
      div class: "min-h-screen flex" do
        left_panel
        right_panel
      end
    end

    private

    def left_panel
      div class: "w-full lg:w-[520px] flex flex-col bg-white px-10 py-10 shrink-0" do
        # Logo
        div class: "flex items-center gap-2.5 mb-14" do
          img(
            src: helpers.asset_path("yagye.png"),
            alt: "Yagye",
            class: "h-9 w-auto"
          )
          span class: "text-xl font-bold text-gray-900 tracking-tight" do
            plain "Yagye"
          end
        end

        # Form area
        div class: "flex-1 flex flex-col justify-center max-w-[380px]" do
          div class: "mb-7" do
            h1 class: "#{UI::Theme::AUTH_TITLE_LG} mb-1.5" do
              plain @title
            end
            if @subtitle
              p class: UI::Theme::PAGE_SUBTITLE do
                plain @subtitle
              end
            end
          end
          yield
        end

        # Footer
        p class: "mt-12 #{UI::Theme::FORM_MUTED}" do
          plain "© #{Time.current.year} Yagye Technologies · "
          a href: "#", class: UI::Theme::LINK_MUTED do
            plain "Privacy"
          end
          plain " · "
          a href: "#", class: UI::Theme::LINK_MUTED do
            plain "Terms"
          end
        end
      end
    end

    def right_panel
      div class: "hidden lg:flex flex-1 flex-col items-center justify-center relative overflow-hidden" do
        # gradient background
        div class: "absolute inset-0 bg-gradient-to-br from-[#2d1b8a] via-[#1e3a8a] to-[#0f2064]"

        # ambient glow
        div class: "absolute -top-40 -right-40 w-[500px] h-[500px] rounded-full bg-purple-500/20 blur-3xl pointer-events-none"
        div class: "absolute -bottom-40 -left-40 w-[500px] h-[500px] rounded-full bg-blue-400/15 blur-3xl pointer-events-none"

        # content
        div class: "relative z-10 px-16 text-center max-w-xl" do
          img(
            src: helpers.asset_path("yagye.png"),
            alt: "Yagye",
            class: "h-20 w-auto mx-auto mb-10 drop-shadow-lg"
          )

          h2 class: "text-4xl font-bold text-white tracking-tight leading-tight mb-5" do
            plain "Africa's payment"
            br
            plain "infrastructure"
          end

          p class: "text-blue-200 text-base leading-relaxed mb-14" do
            plain "Accept payments across mobile money, cards, and bank transfers. " \
                  "Settle in 40+ currencies. Built for scale from day one."
          end

          # Stat cards
          div class: "grid grid-cols-3 gap-4" do
            stat_card("₵ 2.4B", "processed daily")
            stat_card("99.99%", "uptime SLA")
            stat_card("40+", "currencies")
          end
        end
      end
    end

    def stat_card(value, label)
      div class: "rounded-xl bg-white/10 backdrop-blur-sm border border-white/20 px-4 py-4 text-center" do
        p class: "text-xl font-bold text-white mb-0.5" do
          plain value
        end
        p class: "text-xs text-blue-200" do
          plain label
        end
      end
    end
  end
end
