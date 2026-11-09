# frozen_string_literal: true

module Risk
  # Generates a Suspicious Activity Report (SAR) PDF for a flagged payment case.
  # Uses Prawn for PDF generation. Called from FlaggedPaymentsController#sar.
  class SarPdfGenerator
    PAGE_MARGIN    = [50, 50, 50, 50].freeze
    HEADER_COLOR   = "111827"
    MUTED_COLOR    = "6B7280"
    RULE_COLOR     = "E5E7EB"
    LABEL_BG       = "F9FAFB"

    def initialize(payment:, labels:)
      @payment = payment
      @labels  = labels
    end

    def generate
      Prawn::Document.new(page_size: "A4", margin: PAGE_MARGIN) do |pdf|
        render_header(pdf)
        render_payment_section(pdf)
        render_risk_signals(pdf)
        render_disposition_history(pdf)
        render_footer(pdf)
      end
    end

    private

    def render_header(pdf)
      pdf.font_size 18
      pdf.text "Suspicious Activity Report", style: :bold, color: HEADER_COLOR, align: :center
      pdf.move_down 3
      pdf.font_size 10
      pdf.text "Generated: #{Time.current.strftime('%Y-%m-%d %H:%M UTC')}",
               color: MUTED_COLOR, align: :center
      pdf.move_down 3
      pdf.text "Reference: SAR-#{@payment['public_id']}",
               color: MUTED_COLOR, align: :center
      pdf.move_down 16
      pdf.stroke_color RULE_COLOR
      pdf.line_width = 1
      pdf.stroke_horizontal_rule
      pdf.move_down 16
    end

    def render_payment_section(pdf)
      section_title(pdf, "Payment Details")

      rows = [
        ["Payment ID",   @payment["public_id"] || "—"],
        ["Merchant ID",  @payment["merchant_id"] || "—"],
        ["Amount",       format_amount],
        ["Currency",     @payment["currency"] || "GHS"],
        ["Method",       @payment["method"]&.tr("_", " ")&.capitalize || "—"],
        ["State",        @payment["state"]&.capitalize || "—"],
        ["Flagged At",   fmt_datetime(@payment["risk_flagged_at"])]
      ]

      render_table(pdf, rows)
    end

    def render_risk_signals(pdf)
      section_title(pdf, "ML Risk Signals")

      score = @payment["risk_score"]
      rows = [
        ["Risk Score",    score ? format("%.6f", score.to_f) : "—"],
        ["Risk Decision", @payment["risk_decision"]&.capitalize || "—"]
      ]

      render_table(pdf, rows)
    end

    def render_disposition_history(pdf)
      section_title(pdf, "Disposition History")

      if @labels.empty?
        pdf.font_size 10
        pdf.text "No dispositions recorded.", color: MUTED_COLOR
        pdf.move_down 12
        return
      end

      header_row = [
        { content: "Label",     font_style: :bold },
        { content: "Analyst",   font_style: :bold },
        { content: "Timestamp", font_style: :bold },
        { content: "Note",      font_style: :bold }
      ]

      data_rows = @labels.map do |lbl|
        [
          lbl["label"]&.tr("_", " ")&.capitalize || "—",
          lbl["labelled_by"] || "—",
          fmt_datetime(lbl["inserted_at"]),
          lbl["note"].presence || "—"
        ]
      end

      pdf.table([header_row] + data_rows,
                cell_style: { size: 9, padding: [4, 6] },
                column_widths: [100, 110, 120, 170]) do
        row(0).style(background_color: "EEEEEE")
      end
      pdf.move_down 12
    end

    def render_footer(pdf)
      pdf.move_down 10
      pdf.stroke_color RULE_COLOR
      pdf.stroke_horizontal_rule
      pdf.move_down 8
      pdf.font_size 8
      pdf.text "This document is confidential and intended solely for compliance use.",
               color: MUTED_COLOR, align: :center
      pdf.text "Yagye Payments Ltd · Compliance & Risk Division",
               color: MUTED_COLOR, align: :center
      pdf.number_pages "<page> / <total>",
                       at: [ pdf.bounds.right - 60, 0 ],
                       width: 60, align: :right, size: 8
    end

    def section_title(pdf, title)
      pdf.font_size 12
      pdf.text title, style: :bold, color: HEADER_COLOR
      pdf.move_down 6
    end

    def render_table(pdf, rows)
      pdf.table(rows, cell_style: { size: 10, padding: [4, 8] },
                column_widths: [130, 380]) do
        column(0).style(font_style: :bold, background_color: LABEL_BG)
      end
      pdf.move_down 14
    end

    def format_amount
      return "—" unless @payment["amount"]
      n   = @payment["amount"].to_f / 100
      ccy = @payment["currency"] || "GHS"
      "#{ccy} #{format('%.2f', n)}"
    end

    def fmt_datetime(str)
      return "—" if str.blank?
      Time.parse(str.to_s).strftime("%Y-%m-%d %H:%M UTC")
    rescue ArgumentError, TypeError
      str.to_s
    end
  end
end
