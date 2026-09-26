# frozen_string_literal: true

require "csv"

module Exports
  # Pure utility — no domain knowledge.
  # records — any array of objects
  # columns — Hash: { "Display Label" => :method_name_or_proc }
  class CsvExport
    def initialize(records:, columns:)
      @records = records
      @columns = columns
    end

    def call
      CSV.generate(headers: true) do |csv|
        csv << @columns.keys
        @records.each { |record| csv << row_values(record) }
      end
    end

    # Yields one CSV line at a time (header first, then each record row).
    # Use this for streaming responses so memory stays flat and the request
    # doesn't time out on large datasets.
    def stream
      yield CSV.generate_line(@columns.keys)
      @records.find_each(batch_size: 500) { |r| yield CSV.generate_line(row_values(r)) }
    end

    private

    def row_values(record)
      @columns.values.map do |extractor|
        extractor.is_a?(Proc) ? extractor.call(record) : record.public_send(extractor)
      end
    end
  end
end
