defmodule Simulator.Web.ApiSpec do
  @moduledoc """
  OpenAPI spec for the Gateway Simulator.

  This spec documents the provider contract — the API that Yagye's SimulatorAdapter
  calls. Its vocabulary is deliberately NOT Yagye's internal vocabulary.
  If `payment_id`, `pay_`, or `requires_action` appear here, the anti-corruption
  layer has leaked.
  """

  alias OpenApiSpex.{Components, Info, Paths, Schema, SecurityScheme, Server}

  def spec do
    %OpenApiSpex.OpenApi{
      info: %Info{
        title: "Yagye Gateway Simulator",
        version: "1.0.0",
        description: """
        A programmable payment provider simulator for integration testing.

        **Vocabulary is deliberately different from Yagye Core** — `charge_ref` not `payment_id`,
        `AUTHORISED` not `authorised`, `PENDING_AUTH` not `requires_action`. Any crossover
        between these namespaces indicates a broken anti-corruption layer.

        ## Authentication
        All endpoints require `x-api-key`. Issue keys via the admin interface or seeds.

        ## Outcome Control
        Charge outcomes are driven by the active scenario. Set `seed` in the request body
        for deterministic replay — the same seed always produces the same outcome.

        ## Wallet Flow
        Wallet charges (`instrument_type: WALLET`) return `PENDING_AUTH` immediately.
        Poll `GET /charges/:ref` for the resolved state. In production the simulator
        delivers a webhook when the prompt resolves.
        """
      },
      servers: [%Server{url: "http://localhost:4100"}],
      paths: Paths.from_router(Simulator.Web.Router),
      components: %Components{
        securitySchemes: %{
          "api_key" => %SecurityScheme{
            type: "apiKey",
            in: "header",
            name: "x-api-key"
          }
        },
        schemas: %{
          "ChargeRequest" => charge_request_schema(),
          "ChargeResponse" => charge_response_schema(),
          "RefundRequest" => refund_request_schema(),
          "RefundResponse" => refund_response_schema(),
          "NameEnquiryRequest" => name_enquiry_request_schema(),
          "NameEnquiryResponse" => name_enquiry_response_schema(),
          "Error" => error_schema()
        }
      },
      security: [%{"api_key" => []}]
    }
    |> OpenApiSpex.resolve_schema_modules()
  end

  defp charge_request_schema do
    %Schema{
      title: "ChargeRequest",
      type: :object,
      required: [:amount_minor, :currency, :instrument_type],
      properties: %{
        amount_minor: %Schema{
          type: :integer,
          description: "Amount in minor units (e.g. pesewas for GHS)",
          minimum: 1
        },
        currency: %Schema{type: :string, description: "ISO 4217 currency code", example: "GHS"},
        instrument_type: %Schema{
          type: :string,
          enum: ["CARD", "WALLET", "BANK"],
          description: "NOT card|mobile_money — the provider's vocabulary"
        },
        idempotency_key: %Schema{
          type: :string,
          description: "Caller-supplied idempotency key. Safe to retry with same key."
        },
        scenario_id: %Schema{
          type: :string,
          format: :uuid,
          description: "Override the account default scenario for this charge"
        },
        seed: %Schema{
          type: :integer,
          description: "Deterministic replay seed — same seed always produces same outcome"
        },
        network: %Schema{
          type: :string,
          enum: ["MTN", "TELECEL", "AIRTELTIGO"],
          description: "Required for WALLET instrument"
        },
        msisdn: %Schema{
          type: :string,
          description:
            "Subscriber number — scenario range 024000000x only. CI greps for real numbers."
        },
        approval_delay_ms: %Schema{
          type: :integer,
          description: "WALLET: simulated human approval delay in milliseconds"
        }
      }
    }
  end

  defp charge_response_schema do
    %Schema{
      title: "ChargeResponse",
      type: :object,
      properties: %{
        charge_ref: %Schema{
          type: :string,
          description: "Provider charge reference — gw_… NOT pay_…",
          example: "gw_01JXYZ"
        },
        state: %Schema{
          type: :string,
          enum: [
            "PENDING_AUTH",
            "AUTHORISED",
            "CAPTURED",
            "PARTIALLY_CAPTURED",
            "VOIDED",
            "DECLINED",
            "REVERSED",
            "AUTH_EXPIRED"
          ],
          description: "Provider state — NOT Yagye's state machine"
        },
        amount_minor: %Schema{type: :integer},
        currency: %Schema{type: :string},
        instrument_type: %Schema{type: :string},
        auth_code: %Schema{type: :string, nullable: true, description: "Present when AUTHORISED"},
        rrn: %Schema{type: :string, nullable: true, description: "Retrieval Reference Number"},
        arn: %Schema{
          type: :string,
          nullable: true,
          description: "Acquirer Reference Number — timing depends on scenario.arn_issued_at"
        },
        decline_code: %Schema{type: :string, nullable: true, description: "Present when DECLINED"},
        authorised_at: %Schema{type: :string, format: :"date-time", nullable: true},
        created_at: %Schema{type: :string, format: :"date-time"}
      }
    }
  end

  defp refund_request_schema do
    %Schema{
      title: "RefundRequest",
      type: :object,
      required: [:amount_minor],
      properties: %{
        amount_minor: %Schema{
          type: :integer,
          description: "Amount to refund — may be less than original (partial refund)",
          minimum: 1
        }
      }
    }
  end

  defp refund_response_schema do
    %Schema{
      title: "RefundResponse",
      type: :object,
      properties: %{
        refund_ref: %Schema{type: :string, description: "RF_… — provider's refund reference"},
        charge_id: %Schema{type: :string, format: :uuid},
        amount_minor: %Schema{type: :integer},
        currency: %Schema{type: :string},
        state: %Schema{type: :string, enum: ["REQUESTED", "OK", "PARTIAL", "FAILED"]},
        fee_minor: %Schema{
          type: :integer,
          description: "Refund processing fee — 0 for most scenarios"
        },
        refund_arn: %Schema{
          type: :string,
          nullable: true,
          description: "NULL until settlement cycle confirms"
        },
        failure_code: %Schema{type: :string, nullable: true},
        created_at: %Schema{type: :string, format: :"date-time"}
      }
    }
  end

  defp name_enquiry_request_schema do
    %Schema{
      title: "NameEnquiryRequest",
      type: :object,
      required: [:network, :msisdn],
      properties: %{
        network: %Schema{type: :string, enum: ["MTN", "TELECEL", "AIRTELTIGO"]},
        msisdn: %Schema{
          type: :string,
          description: "Scenario number — 024000000x range. Ending in 0 = NOT_FOUND."
        },
        charge_id: %Schema{
          type: :string,
          format: :uuid,
          description: "Associate enquiry with an in-flight charge"
        },
        delay_ms: %Schema{type: :integer, description: "Simulated network round-trip in ms"}
      }
    }
  end

  defp name_enquiry_response_schema do
    %Schema{
      title: "NameEnquiryResponse",
      type: :object,
      properties: %{
        outcome: %Schema{type: :string, enum: ["FOUND", "NOT_FOUND", "TIMEOUT", "NETWORK_ERROR"]},
        account_name: %Schema{
          type: :string,
          nullable: true,
          description: "NULL when outcome is not FOUND"
        },
        network: %Schema{type: :string},
        msisdn: %Schema{type: :string},
        queried_at: %Schema{type: :string, format: :"date-time"}
      }
    }
  end

  defp error_schema do
    %Schema{
      title: "Error",
      type: :object,
      properties: %{
        error: %Schema{type: :string},
        message: %Schema{type: :string, nullable: true}
      }
    }
  end
end
