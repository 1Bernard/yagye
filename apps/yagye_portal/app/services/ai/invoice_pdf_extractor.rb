# frozen_string_literal: true

module Ai
  # Extracts structured invoice data from a PDF.
  #
  # Preferred path: when LLM_PROVIDER=anthropic the PDF bytes are sent directly
  # to the native Anthropic Messages API as a document block so Claude reads the
  # visual layout — multi-column tables extract correctly without text-order issues.
  #
  # Fallback: pdf-reader text extraction + LLM chat for other providers.
  class InvoicePdfExtractor
    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an invoice data extraction assistant.
      Return ONLY valid JSON — no markdown fences, no explanation, no preamble.
      Use null for any field you cannot determine with confidence.

      CRITICAL RULES:
      - customer_reference is the BILL TO party — the company or person being invoiced.
        Do NOT put the seller/issuer/vendor name here.
      - unit_amount must be the PRE-TAX unit price printed in the invoice's "Unit Price" column.
        NEVER compute or include tax in unit_amount.
      - tax_rate_bps is the tax rate in basis points: 8.25% = 825, 15% = 1500.
        Read the EXACT rate from the invoice — do not round (e.g. do not round 8.25% to 8.3%).
      - discount_amount is the total discount as a positive decimal (e.g. 369.55), not negative.
      - Monetary amounts are decimal numbers in the invoice's currency units (e.g. 50.00, not 5000).
      - Dates must be in YYYY-MM-DD format.
      - Currency must be a 3-letter ISO code (e.g. GHS, USD, NGN).
      - If the invoice is garbled or unreadable, return exactly: {"error":"unreadable"}
    PROMPT

    EXTRACTION_PROMPT = <<~MSG.freeze
      Extract all invoice data and return a JSON object with these keys:
      - number              (string)  invoice number or reference
      - issue_date          (string)  YYYY-MM-DD
      - due_date            (string)  YYYY-MM-DD
      - customer_reference  (string)  the BILL TO name — the customer receiving this invoice
      - currency            (string)  3-letter ISO code
      - discount_amount     (number)  total discount as a positive decimal, or null
      - notes               (string)  payment notes, late-fee terms, or null
      - line_items          (array)   each with:
          description   (string)   full line item description
          quantity      (number)   quantity as printed
          unit_amount   (number)   unit price PRE-TAX as printed in the "Unit Price" column
          tax_rate_bps  (integer)  tax rate in basis points (e.g. 825 for 8.25%), 0 if none

      Read the exact tax rate — do not approximate (8.25% ≠ 8.3%).
      unit_amount must match the "Unit Price" column, not the extended amount or total.
    MSG

    Result = Struct.new(:fields, :error, keyword_init: true) do
      def success? = error.nil?
    end

    # Primary entry point. Tries native Anthropic PDF API first (accurate layout reading),
    # falls back to pdf-reader text extraction for other providers.
    def extract_from_bytes(pdf_bytes)
      client = Ai::AnthropicClient.new

      if client.supports_pdf?
        result = client.chat_with_pdf(pdf_bytes: pdf_bytes, system: SYSTEM_PROMPT, prompt: EXTRACTION_PROMPT)
        return Result.new(error: result.error) unless result.success?
        parse_result(result.text)
      else
        text = extract_text_from_bytes(pdf_bytes)
        extract(text)
      end
    rescue StandardError => e
      Rails.logger.error("[Ai::InvoicePdfExtractor] #{e.class}: #{e.message}")
      Result.new(error: "Extraction failed — please enter invoice details manually.")
    end

    # Text-based fallback. Called directly when only extracted text is available.
    def extract(pdf_text)
      if pdf_text.blank?
        return Result.new(error: "PDF appears to be empty or image-based — please enter invoice details manually.")
      end

      prompt = "#{EXTRACTION_PROMPT}\n\nINVOICE TEXT:\n#{pdf_text.truncate(8_000)}"

      result = Ai::AnthropicClient.new.chat(
        system:   SYSTEM_PROMPT,
        messages: [ { role: "user", content: prompt } ]
      )

      return Result.new(error: result.error) unless result.success?
      parse_result(result.text)
    rescue StandardError => e
      Rails.logger.error("[Ai::InvoicePdfExtractor] #{e.class}: #{e.message}")
      Result.new(error: "Extraction failed — please enter invoice details manually.")
    end

    private

    def parse_result(text)
      raw    = text.gsub(/\A```(?:json)?\n?|\n?```\z/, "").strip
      parsed = JSON.parse(raw)
      return Result.new(error: "Invoice PDF is unreadable — please enter details manually.") if parsed["error"]
      Result.new(fields: normalize(parsed))
    rescue JSON::ParserError => e
      Rails.logger.warn("[Ai::InvoicePdfExtractor] JSON parse failed: #{e.message.truncate(200)}")
      Result.new(error: "Could not parse extraction result — please enter invoice details manually.")
    end

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

    def extract_text_from_bytes(pdf_bytes)
      require "tempfile"
      tmp = Tempfile.new([ "invoice", ".pdf" ])
      tmp.binmode
      tmp.write(pdf_bytes)
      tmp.rewind
      PDF::Reader.new(tmp.path).pages.map(&:text).join("\n").strip
    rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError
      ""
    ensure
      tmp&.close
      tmp&.unlink
    end
  end
end
