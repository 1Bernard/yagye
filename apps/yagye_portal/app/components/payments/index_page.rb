module Payments
  class IndexPage < ApplicationComponent
    def initialize(payments:, pagy:, can_view_pii: false, can_export: false, status_filter: nil, query: nil)
      @payments      = payments
      @pagy          = pagy
      @can_view_pii  = can_view_pii
      @can_export    = can_export
      @status_filter = status_filter
      @query         = query
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :payments,
        title: "Payments",
        subtitle: "All transactions processed through your account"
      ) do
        stat_row
        filter_bar
        payments_table
        pagination_row
      end
    end

    private

    def stat_row
      div class: "grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6" do
        render UI::StatCard.new(label: "Volume (MTD)",       value: "GHS 0.00")
        render UI::StatCard.new(label: "Transactions (MTD)", value: "0")
        render UI::StatCard.new(label: "Pending",            value: "0")
        render UI::StatCard.new(label: "Failed",             value: "0")
      end
    end

    def filter_bar
      div class: "flex items-center gap-3 mb-4" do
        search_form
        status_form
        div class: "ml-auto flex items-center gap-2" do
          if @can_export
            a href: "#", class: UI::Theme::BUTTON_SECONDARY do
              plain "Export CSV"
            end
          end
        end
      end
    end

    def search_form
      div class: "relative flex-1 max-w-xs" do
        span class: "absolute inset-y-0 left-3 flex items-center pointer-events-none #{UI::Theme::NAV_ICON_OFF}" do
          svg search_icon
        end
        form method: :get, action: payments_path do
          input(
            type: :text,
            name: :q,
            value: @query,
            placeholder: "Search reference or customer...",
            class: "#{UI::Theme::SEARCH_INPUT} w-full pl-9 pr-3 py-2"
          )
        end
      end
    end

    def status_form
      form method: :get, action: payments_path do
        input(type: :hidden, name: :q, value: @query) if @query.present?
        select(
          name: :status,
          onchange: "this.form.submit()",
          class: "#{UI::Theme::INPUT} py-2 pr-8 cursor-pointer"
        ) do
          option(value: "", selected: @status_filter.blank?) { plain "All statuses" }
          %w[initiated processing paid failed refunded disputed].each do |s|
            option(value: s, selected: @status_filter == s) { plain s.capitalize }
          end
        end
      end
    end

    def payments_table
      div class: "#{UI::Theme::CARD} overflow-hidden mb-4" do
        if @payments.empty?
          empty_state
        else
          div class: "overflow-x-auto" do
            table class: "w-full" do
              thead do
                tr class: "border-b border-gray-100" do
                  th(class: UI::Theme::TH) { plain "Reference" }
                  th(class: UI::Theme::TH) { plain "Customer" }
                  th(class: "#{UI::Theme::TH} text-right") { plain "Amount" }
                  th(class: UI::Theme::TH) { plain "Status" }
                  th(class: UI::Theme::TH) { plain "Provider" }
                  th(class: UI::Theme::TH) { plain "Date" }
                end
              end
              tbody do
                @payments.each { |p| payment_row(p) }
              end
            end
          end
        end
      end
    end

    def payment_row(payment)
      tr class: "border-b border-gray-50 hover:bg-gray-50 transition-colors" do
        td class: UI::Theme::TD do
          span class: "font-mono text-xs text-gray-900" do
            plain payment.reference.presence || payment.core_payment_id.first(12)
          end
        end
        td class: UI::Theme::TD do
          plain @can_view_pii ? (payment.customer_msisdn || "—") : payment.masked_msisdn
        end
        td class: "#{UI::Theme::TD} text-right tabular-nums font-medium" do
          plain payment.formatted_amount
        end
        td class: UI::Theme::TD do
          render UI::StatusBadge.new(status: payment.status)
        end
        td class: "#{UI::Theme::TD} text-gray-500" do
          plain payment.provider_label
        end
        td class: "#{UI::Theme::TD} text-xs text-gray-400" do
          plain payment.created_at.strftime("%d %b %Y, %H:%M")
        end
      end
    end

    def empty_state
      div class: "py-16 text-center" do
        p class: "#{UI::Theme::MUTED} mb-1" do
          plain "No payments found"
        end
        p class: "text-xs text-gray-400" do
          if @status_filter.present? || @query.present?
            plain "Try adjusting your filters."
          else
            plain "Payments will appear here once transactions are processed."
          end
        end
      end
    end

    def pagination_row
      return unless @pagy.pages > 1

      div class: "flex items-center justify-between px-1" do
        p class: UI::Theme::MUTED do
          plain "Showing #{@pagy.from}–#{@pagy.to} of #{@pagy.count}"
        end
        div class: "flex items-center gap-1" do
          if @pagy.previous
            a href: payments_path(page: @pagy.previous, status: @status_filter, q: @query),
              class: UI::Theme::BUTTON_SECONDARY do
              plain "← Previous"
            end
          end
          if @pagy.next
            a href: payments_path(page: @pagy.next, status: @status_filter, q: @query),
              class: UI::Theme::BUTTON_PRIMARY do
              plain "Next →"
            end
          end
        end
      end
    end

    def search_icon
      %(<svg class="w-4 h-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clip-rule="evenodd"/></svg>)
    end
  end
end
