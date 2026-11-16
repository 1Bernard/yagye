# frozen_string_literal: true

module Ai
  # Extracts structured invoice data from PDF text using the configured LLM.
  # Returns a Result with a normalized fields hash on success.
  class InvoicePdfExtractor
    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an invoice data extraction assistant. Extract structured invoice data from the provided text.
      Return ONLY valid JSON — no markdown fences, no explanation, no preamble.
      Use null for any field you cannot determine with confidence.
      Monetary amounts must be decimal numbers in the invoice's own currency units (e.g. 50.00, not 5000).
      Dates must be in YYYY-MM-DD format. Currency must be a 3-letter ISO code (e.g. GHS, USD, NGN).
      If the text is garbled, too short, or clearly unreadable, return exactly: {"error":"unreadable"}
    PROMPT

    Result = Struct.new(:fields, :error, keyword_init: true) do
      def success? = error.nil?
    end

    def extract(pdf_text)
      if pdf_text.blank?
        return Result.new(error: "PDF appears to be empty or image-based — please enter invoice details manually.")
      end

      prompt = <<~MSG
        Extract all invoice data from the following text and return a JSON object with these keys:
        - number         (string)  invoice number or reference
        - issue_date     (string)  YYYY-MM-DD
        - due_date       (string)  YYYY-MM-DD
        - customer_reference (string) customer name, company or reference
        - currency       (string)  3-letter ISO code
        - discount_amount (number) decimal amount, or null
        - notes          (string)  payment notes or null
        - line_items     (array)   each with: description, quantity (number), unit_amount (number), tax_rate_bps (integer, e.g. 1500 for 15%)

        INVOICE TEXT:
        #{pdf_text.truncate(8_000)}
      MSG

      result = Ai::AnthropicClient.new.chat(
        system:   SYSTEM_PROMPT,
        messages: [ { role: "user", content: prompt } ]
      )

      return Result.new(error: result.error) unless result.success?

      begin
        raw    = result.text.gsub(/\A```(?:json)?\n?|\n?```\z/, "").strip
        parsed = JSON.parse(raw)
        return Result.new(error: "Invoice PDF is unreadable — please enter details manually.") if parsed["error"]

        Result.new(fields: normalize(parsed))
      rescue JSON::ParserError => e
        Rails.logger.warn("[Ai::InvoicePdfExtractor] JSON parse failed: #{e.message.truncate(200)}")
        Result.new(error: "Could not parse extraction result — please enter invoice details manually.")
      end
    rescue StandardError => e
      Rails.logger.error("[Ai::InvoicePdfExtractor] #{e.class}: #{e.message}")
      Result.new(error: "Extraction failed — please enter invoice details manually.")
    end

    private

    def normalize(parsed)
      {
        "number"             => parsed["number"].presence,
        "issue_date"         => parsed["issue_date"].presence,
        "due_date"           => parsed["due_date"].presence,
        "customer_reference" => parsed["customer_reference"].presence,
        "currency"           => parsed["currency"].presence&.upcase,
        "discount_amount"    => parsed["discount_amount"]&.to_f&.round(2),
        "notes"              => parsed["notes"].presence,
        "line_items"         => normalize_line_items(parsed["line_items"])
      }
    end

    def normalize_line_items(items)
      return [] unless items.is_a?(Array)

      items.filter_map do |item|
        next unless item.is_a?(Hash)
        {
          "description"  => item["description"].to_s.presence,
          "quantity"     => item["quantity"].to_f.round(4),
          "unit_amount"  => item["unit_amount"].to_f.round(2),
          "tax_rate_bps" => item["tax_rate_bps"].to_i
        }
      end
    end
  end
end
