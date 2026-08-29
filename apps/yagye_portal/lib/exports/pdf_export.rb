# frozen_string_literal: true

module Exports
  # Pure utility — returns PDF bytes. Requires gems "prawn" and "prawn-table".
  class PdfExport
    def initialize(records:, columns:, title: "Report")
      @records = records
      @columns = columns
      @title   = title
    end

    def call
      pdf = Prawn::Document.new(page_layout: :landscape, margin: [30, 30, 30, 30])
      render_header(pdf)
      render_table(pdf)
      render_footer(pdf)
      pdf.render
    end

    private

    def render_header(pdf)
      pdf.font_size(18) { pdf.text @title, style: :bold }
      pdf.font_size(9)  { pdf.text "Generated: #{Time.current.strftime('%Y-%m-%d %H:%M')}" }
      pdf.move_down(14)
    end

    def render_table(pdf)
      rows = build_rows
      return pdf.text("No records found.", size: 10) if rows.size <= 1

      pdf.table(rows,
                header: true,
                width:  pdf.bounds.width,
                cell_style: { size: 9, padding: [5, 8, 5, 8], border_color: "CBD5E1" }) do |t|
        style_rows(t, rows.size)
      end
    end

    def style_rows(table, row_count)
      table.row(0).background_color = "F1F5F9"
      table.row(0).font_style       = :bold
      table.row(0).text_color       = "0F172A"
      (1..(row_count - 1)).each do |i|
        table.row(i).background_color = i.odd? ? "FFFFFF" : "F8FAFC"
      end
    end

    def render_footer(pdf)
      pdf.number_pages("<page> / <total>",
                       at: [pdf.bounds.right - 60, 0],
                       width: 60, align: :right, size: 8)
    end

    def build_rows
      header = @columns.keys
      data   = @records.map do |record|
        @columns.values.map do |extractor|
          val = extractor.is_a?(Proc) ? extractor.call(record) : record.public_send(extractor)
          val.to_s
        end
      end
      [header] + data
    end
  end
end
