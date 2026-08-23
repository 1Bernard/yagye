defmodule YagyeCore.Events do
  @moduledoc false

  # Writes a domain event into outbox_messages in the SAME database transaction
  # as the state change. Call this inside an existing Repo.transaction block:
  #
  #   Repo.transaction(fn ->
  #     with {:ok, payment} <- update_payment(payment),
  #          {:ok, _msg}    <- Events.emit(payment, "payment.succeeded", payload) do
  #       payment
  #     else
  #       {:error, reason} -> Repo.rollback(reason)
  #     end
  #   end)
  #
  # The caller owns the transaction. Events.emit never opens its own transaction.

  alias YagyeCore.Events.EventEnvelope
  alias YagyeCore.Events.Schemas.OutboxMessage
  alias YagyeCore.Repo

  @doc """
  Emits a domain event by inserting a row into outbox_messages.

  aggregate     - the Ecto struct (Payment, Merchant, …). Used to derive
                  aggregate_type, aggregate_id, aggregate_version, merchant_id, mode.
  event_type    - string event name, e.g. "payment.succeeded"
  payload       - map of event-specific data
  opts:
    :event_version  - schema version of this event (default: 1)
    :destination    - delivery target (default: "internal:projections")
    :correlation_id - optional trace propagation string
  """
  @spec emit(struct(), String.t(), map(), keyword()) ::
          {:ok, OutboxMessage.t()} | {:error, Ecto.Changeset.t()}
  def emit(aggregate, event_type, payload, opts \\ []) do
    event_version = Keyword.get(opts, :event_version, 1)
    destination = Keyword.get(opts, :destination, "internal:projections")
    correlation_id = Keyword.get(opts, :correlation_id)
    now = DateTime.utc_now()

    envelope = %EventEnvelope{
      event_id: Uniq.UUID.uuid7(),
      event_type: event_type,
      event_version: event_version,
      aggregate_type: aggregate_type(aggregate),
      aggregate_id: aggregate.id,
      aggregate_version: Map.get(aggregate, :version, 0),
      merchant_id: Map.get(aggregate, :merchant_id),
      mode: Map.get(aggregate, :mode, "simulation"),
      correlation_id: correlation_id,
      occurred_at: now,
      payload: payload
    }

    %OutboxMessage{}
    |> OutboxMessage.changeset(%{
      event_id: envelope.event_id,
      aggregate_type: envelope.aggregate_type,
      aggregate_id: envelope.aggregate_id,
      aggregate_version: envelope.aggregate_version,
      event_type: envelope.event_type,
      event_version: envelope.event_version,
      partition_key: to_string(envelope.aggregate_id),
      merchant_id: envelope.merchant_id,
      destination: destination,
      envelope: EventEnvelope.to_map(envelope),
      mode: envelope.mode,
      occurred_at: now
    })
    |> Repo.insert()
  end

  # Derives a stable string aggregate type from the Ecto struct module name.
  # YagyeCore.Payments.Schemas.Payment → "payment"
  defp aggregate_type(aggregate) do
    aggregate.__struct__
    |> Module.split()
    |> List.last()
    |> String.downcase()
  end
end
