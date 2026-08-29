# frozen_string_literal: true

module Exports
  # Pure utility — returns xlsx bytes. Requires gem "caxlsx".
  class ExcelExport
    def initialize(records:, columns:, sheet_name: "Report")
      @records    = records
      @columns    = columns
      @sheet_name = sheet_name
    end

    def call
      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: @sheet_name) { |sheet| build_sheet(sheet) }
      package.to_stream.read
    end

    private

    def build_sheet(sheet)
      header_style, data_style = build_styles(sheet)
      add_rows(sheet, header_style, data_style)
      freeze_header_row(sheet)
    end

    def build_styles(sheet)
      styles = sheet.styles
      header_style = styles.add_style(
        bg_color: "F1F5F9", fg_color: "0F172A", b: true, sz: 11,
        border: { style: :thin, color: "CBD5E1" }
      )
      data_style = styles.add_style(sz: 10, border: { style: :thin, color: "E2E8F0" })
      [header_style, data_style]
    end

    def add_rows(sheet, header_style, data_style)
      sheet.add_row @columns.keys, style: header_style
      @records.each { |record| sheet.add_row row_values(record), style: data_style }
    end

    def freeze_header_row(sheet)
      sheet.sheet_view.pane do |pane|
        pane.top_left_cell = "A2"
        pane.state         = :frozen_split
        pane.y_split       = 1
        pane.x_split       = 0
        pane.active_pane   = :bottom_right
      end
    end

    def row_values(record)
      @columns.values.map do |extractor|
        value = extractor.is_a?(Proc) ? extractor.call(record) : record.public_send(extractor)
        value.is_a?(Numeric) ? value : value.to_s
      end
    end
  end
end
