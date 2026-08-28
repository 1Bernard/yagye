module Layout
  class Shell < ApplicationComponent
    def initialize(active_nav:, title:, subtitle: nil, &content)
      @active_nav = active_nav
      @title      = title
      @subtitle   = subtitle
      @content    = content
    end

    def view_template
      div class: "flex min-h-screen bg-gray-50 font-sans" do
        render Layout::Sidebar.new(active: @active_nav)

        div class: "flex-1 flex flex-col min-w-0" do
          render Layout::Topbar.new(title: @title, subtitle: @subtitle)

          main class: "flex-1 p-6 overflow-auto" do
            yield
          end
        end
      end
    end
  end
end
