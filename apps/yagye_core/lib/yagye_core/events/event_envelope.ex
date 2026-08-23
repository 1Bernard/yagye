defmodule YagyeCore.Events.EventEnvelope do
  @moduledoc false

  # The normalized shape written into outbox_messages.envelope (jsonb).
  # Every domain event travels as this struct — aggregate metadata lives
  # outside the payload so consumers can filter without parsing the payload.

  @enforce_keys [
    :event_id,
    :event_type,
    :event_version,
    :aggregate_type,
    :aggregate_id,
    :aggregate_version,
    :mode,
    :occurred_at,
    :payload
  ]

  defstruct [
    :event_id,
    :event_type,
    :event_version,
    :aggregate_type,
    :aggregate_id,
    :aggregate_version,
    :merchant_id,
    :mode,
    :correlation_id,
    :occurred_at,
    :payload
  ]

  @type t :: %__MODULE__{
          event_id: String.t(),
          event_type: String.t(),
          event_version: pos_integer(),
          aggregate_type: String.t(),
          aggregate_id: String.t(),
          aggregate_version: non_neg_integer(),
          merchant_id: String.t() | nil,
          mode: String.t(),
          correlation_id: String.t() | nil,
          occurred_at: DateTime.t(),
          payload: map()
        }

  def to_map(%__MODULE__{} = env) do
    %{
      "event_id" => env.event_id,
      "event_type" => env.event_type,
      "event_version" => env.event_version,
      "aggregate_type" => env.aggregate_type,
      "aggregate_id" => env.aggregate_id,
      "aggregate_version" => env.aggregate_version,
      "merchant_id" => env.merchant_id,
      "mode" => env.mode,
      "correlation_id" => env.correlation_id,
      "occurred_at" => DateTime.to_iso8601(env.occurred_at),
      # JSON roundtrip normalises all keys to strings so JSONB reads are consistent
      "payload" => env.payload |> Jason.encode!() |> Jason.decode!()
    }
  end

  def from_map(%{} = map) do
    {:ok, occurred_at, _} = DateTime.from_iso8601(map["occurred_at"])

    %__MODULE__{
      event_id: map["event_id"],
      event_type: map["event_type"],
      event_version: map["event_version"],
      aggregate_type: map["aggregate_type"],
      aggregate_id: map["aggregate_id"],
      aggregate_version: map["aggregate_version"],
      merchant_id: map["merchant_id"],
      mode: map["mode"],
      correlation_id: map["correlation_id"],
      occurred_at: occurred_at,
      payload: map["payload"]
    }
  end
end
