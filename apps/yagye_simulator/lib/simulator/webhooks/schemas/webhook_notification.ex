defmodule Simulator.Webhooks.Schemas.WebhookNotification do
  @moduledoc false

  @derive Jason.Encoder
  defstruct [:event_id, :event_type, :charge_ref, :occurred_at, :auth_code, :decline_code]

  @type t :: %__MODULE__{
          event_id: String.t(),
          event_type: String.t(),
          charge_ref: String.t(),
          occurred_at: DateTime.t(),
          auth_code: String.t() | nil,
          decline_code: String.t() | nil
        }

  def build(charge, wallet_prompt) do
    %__MODULE__{
      event_id: Uniq.UUID.uuid7(),
      event_type: event_type(wallet_prompt.prompt_state),
      charge_ref: charge.charge_ref,
      occurred_at: wallet_prompt.resolved_at || DateTime.utc_now(),
      auth_code: charge.auth_code,
      decline_code: decline_code_for(wallet_prompt.prompt_state, wallet_prompt.decline_code)
    }
  end

  defp event_type("APPROVED"), do: "charge.succeeded"
  defp event_type("DECLINED"), do: "charge.failed"
  defp event_type("EXPIRED"), do: "charge.failed"

  defp decline_code_for("DECLINED", code) when is_binary(code), do: code
  defp decline_code_for("DECLINED", _), do: "DECLINED_BY_CUSTOMER"
  defp decline_code_for("EXPIRED", _), do: "PROMPT_EXPIRED"
  defp decline_code_for(_, _), do: nil
end
