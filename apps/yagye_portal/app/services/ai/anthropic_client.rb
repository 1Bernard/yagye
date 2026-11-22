# frozen_string_literal: true

module Ai
  # Faraday wrapper for LLM chat with tool-calling support.
  # Defaults to Groq (free, OpenAI-compatible). Falls back gracefully when
  # the API key is missing so the app boots without it configured.
  #
  # Provider is selected via LLM_PROVIDER env var:
  #   LLM_PROVIDER=groq     → Groq (free, Llama 3.3 70B)   [default]
  #   LLM_PROVIDER=gemini   → Google Gemini Flash (free tier)
  #   LLM_PROVIDER=anthropic → Anthropic Claude Sonnet
  #
  # All three use the OpenAI-compatible chat completions format.
  # Gemini and Groq both expose /v1/chat/completions with tool_calls.
  class AnthropicClient
    PROVIDERS = {
      "groq" => {
        url:   "https://api.groq.com/openai/v1/",
        model: "qwen/qwen3.8-27b",
        key_env: "GROQ_API_KEY"
      },
      "gemini" => {
        url:   "https://generativelanguage.googleapis.com/v1beta/openai/",
        model: "gemini-2.0-flash",
        key_env: "GEMINI_API_KEY"
      },
      "anthropic" => {
        url:   "https://api.anthropic.com/v1/",
        model: "claude-sonnet-5-5",
        key_env: "ANTHROPIC_API_KEY"
      }
    }.freeze

    MAX_TOKENS    = 2048
    MAX_TOOL_ITERS = 5

    Result = Struct.new(:text, :error, keyword_init: true) do
      def success? = error.nil?
    end

    def initialize
      @provider = PROVIDERS.fetch(ENV.fetch("LLM_PROVIDER", "groq"), PROVIDERS["groq"])
      @conn = Faraday.new(url: @provider[:url]) do |f|
        f.request  :json
        f.response :json, content_type: /\bjson$/
        f.request  :retry, max: 2, interval: 0.5,
                           retry_statuses: [ 429, 502, 503, 504 ]
        f.adapter  Faraday.default_adapter
        f.options.timeout      = 60
        f.options.open_timeout = 10
      end
    end

    # Runs the tool-calling loop until the model returns a final text answer.
    # on_tool: lambda called with (tool_name, input_hash) → result hash
    def supports_pdf?
      @provider[:key_env] == "ANTHROPIC_API_KEY"
    end

    # Sends a PDF (raw bytes) directly to the native Anthropic Messages API as a document block.
    # Claude reads the visual layout, so multi-column tables extract correctly.
    # Only callable when supports_pdf? is true; raises otherwise.
    def chat_with_pdf(pdf_bytes:, system:, prompt:)
      raise "PDF extraction requires LLM_PROVIDER=anthropic" unless supports_pdf?

      encoded = Base64.strict_encode64(pdf_bytes)

      native = Faraday.new(url: "https://api.anthropic.com/v1/") do |f|
        f.request  :json
        f.response :json, content_type: /\bjson$/
        f.request  :retry, max: 2, interval: 0.5, retry_statuses: [ 429, 502, 503, 504 ]
        f.adapter  Faraday.default_adapter
        f.options.timeout      = 60
        f.options.open_timeout = 10
      end

      body = {
        model:      @provider[:model],
        max_tokens: MAX_TOKENS,
        system:     system,
        messages:   [ {
          role:    "user",
          content: [
            { type: "document", source: { type: "base64", media_type: "application/pdf", data: encoded } },
            { type: "text", text: prompt }
          ]
        } ]
      }

      response = native.post("messages", body, {
        "x-api-key"         => ENV.fetch("ANTHROPIC_API_KEY"),
        "anthropic-version" => "2023-06-01",
        "Content-Type"      => "application/json"
      })

      if response.success?
        text = response.body.dig("content", 0, "text").to_s
        Result.new(text: text)
      else
        err = response.body.is_a?(Hash) ? response.body.dig("error", "message") : nil
        Result.new(error: err || "Anthropic PDF API error (#{response.status})")
      end
    rescue StandardError => e
      Result.new(error: e.message)
    end

    def chat(system:, messages:, tools: [], on_tool: nil)
      # Prepend system as a system-role message (OpenAI format)
      conversation = [ { role: "system", content: system } ] + messages.dup

      MAX_TOOL_ITERS.times do
        response = call_api(messages: conversation, tools: tools)
        return Result.new(error: response[:error]) unless response[:ok]

        body        = response[:body]
        choice      = body.dig("choices", 0)
        finish      = choice&.dig("finish_reason")
        message     = choice&.dig("message") || {}

        if finish == "stop"
          return Result.new(text: clean_content(message["content"].to_s))
        end

        if finish == "tool_calls" && on_tool
          tool_calls = message["tool_calls"] || []

          # Qwen3 / some models return finish_reason "tool_calls" with no calls populated —
          # fall back to whatever text the model produced rather than erroring.
          if tool_calls.empty?
            text = clean_content(message["content"].to_s)
            return Result.new(text: text.presence || "No response.")
          end

          # Strip thinking tokens from content before adding to conversation history.
          # Qwen3 on Groq injects <think>…</think> blocks into the assistant message;
          # leaving them in causes the NEXT API call to be rejected with a 400.
          tool_call_msg = message.dup
          if tool_call_msg["content"].is_a?(String)
            stripped = strip_thinking(tool_call_msg["content"])
            tool_call_msg["content"] = stripped.empty? ? nil : stripped
          end
          conversation << tool_call_msg

          # Execute each tool and add results
          tool_calls.each do |tc|
            fn     = tc.dig("function") || {}
            name   = fn["name"]
            input  = JSON.parse(fn["arguments"] || "{}")

            result = begin
              on_tool.call(name, input)
            rescue StandardError => e
              Rails.logger.warn("[Ai::ChatClient] tool #{name} failed: #{e.message}")
              { error: e.message }
            end

            conversation << {
              role:         "tool",
              tool_call_id: tc["id"],
              content:      result.to_json
            }
          end
        else
          # Unexpected finish — return whatever content we have
          return Result.new(text: clean_content(message["content"].to_s).presence || "No response.")
        end
      end

      Result.new(text: "I wasn't able to retrieve that information — the data lookup took too many steps. Please try rephrasing your question.")
    end

    private

    def call_api(messages:, tools:)
      body = {
        model:      @provider[:model],
        max_tokens: MAX_TOKENS,
        messages:   messages
      }

      if tools.any?
        # Convert Anthropic-style tool definitions to OpenAI format
        body[:tools] = tools.map do |t|
          {
            type:     "function",
            function: {
              name:        t[:name] || t["name"],
              description: t[:description] || t["description"],
              parameters:  t[:input_schema] || t["input_schema"] || { type: "object", properties: {} }
            }
          }
        end
      end

      response = @conn.post("chat/completions", body, request_headers)

      if response.success?
        { ok: true, body: response.body }
      else
        rb  = response.body
        err = if rb.is_a?(Hash)
          rb.dig("error", "message") || rb["error"]&.to_s || rb.to_json.first(300)
        else
          rb.to_s.first(300)
        end
        Rails.logger.error("[Ai::AnthropicClient] API #{response.status}: #{err}")
        { ok: false, error: err || "LLM API error (#{response.status})" }
      end
    rescue Faraday::Error => e
      Rails.logger.error("[Ai::AnthropicClient] Faraday error: #{e.message}")
      { ok: false, error: e.message }
    end

    def request_headers
      {
        "Authorization" => "Bearer #{api_key}",
        "Content-Type"  => "application/json"
      }
    end

    def api_key
      key_env = @provider[:key_env]
      ENV.fetch(key_env) do
        raise "#{key_env} is not set — AI chat unavailable"
      end
    end

    # Remove Qwen3 thinking tokens that must not appear in conversation history.
    def strip_thinking(text)
      text.to_s.gsub(/<think>.*?<\/think>/m, "").strip
    end

    # Strip thinking tokens and normalise the final content returned to callers.
    def clean_content(text)
      strip_thinking(text)
    end
  end
end
