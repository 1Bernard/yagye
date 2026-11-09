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
                           retry_statuses: [429, 502, 503, 504]
        f.adapter  Faraday.default_adapter
        f.options.timeout      = 60
        f.options.open_timeout = 10
      end
    end

    # Runs the tool-calling loop until the model returns a final text answer.
    # on_tool: lambda called with (tool_name, input_hash) → result hash
    def chat(system:, messages:, tools: [], on_tool: nil)
      # Prepend system as a system-role message (OpenAI format)
      conversation = [{ role: "system", content: system }] + messages.dup

      MAX_TOOL_ITERS.times do
        response = call_api(messages: conversation, tools: tools)
        return Result.new(error: response[:error]) unless response[:ok]

        body        = response[:body]
        choice      = body.dig("choices", 0)
        finish      = choice&.dig("finish_reason")
        message     = choice&.dig("message") || {}

        if finish == "stop"
          return Result.new(text: message["content"].to_s)
        end

        if finish == "tool_calls" && on_tool
          tool_calls = message["tool_calls"] || []
          return Result.new(error: "no tool calls") if tool_calls.empty?

          # Add assistant message (with tool_calls) to conversation
          conversation << message

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
          return Result.new(text: message["content"].to_s.presence || "No response.")
        end
      end

      Result.new(error: "tool call loop exceeded #{MAX_TOOL_ITERS} iterations")
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
        err = response.body.is_a?(Hash) ? response.body.dig("error", "message") : nil
        { ok: false, error: err || "LLM API error (#{response.status})" }
      end
    rescue Faraday::Error => e
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
  end
end
