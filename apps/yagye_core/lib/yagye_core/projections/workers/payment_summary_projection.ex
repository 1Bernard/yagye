defmodule YagyeCore.Projections.Workers.PaymentSummaryProjection do
  @moduledoc false

  # Updates proj_payment_summaries from payment.* events.
  #
  # Version fence: apply only if envelope.aggregate_version > stored.aggregate_version.
  # This makes the worker safe to retry — replaying an older event is a no-op.

  use Oban.Worker, queue: :projections, max_attempts: 5

  alias YagyeCore.Outbox.EventEnvelope
  alias YagyeCore.Projections.Schemas.PaymentSummary
  alias YagyeCore.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"envelope" => raw_envelope}}) do
    envelope = EventEnvelope.from_map(raw_envelope)
    apply_event(envelope)
  end

  # ── Event handlers ────────────────────────────────────────────────────────────

  # All events share the same version-fence flow:
  #   1. Read the current row (nil = not yet projected)
  #   2. If stored version >= incoming version → idempotent no-op
  #   3. Otherwise insert or update

  defp apply_event(%EventEnvelope{event_type: "payment.created"} = env) do
    p = env.payload

    attrs = %{
      payment_id: env.aggregate_id,
      merchant_id: env.merchant_id,
      mode: env.mode,
      aggregate_version: env.aggregate_version,
      state: "created",
      method: p["method"],
      amount: p["amount"],
      currency: p["currency"],
      merchant_reference: p["merchant_reference"],
      customer_reference: p["customer_reference"],
      created_at: env.occurred_at,
      last_transition_at: env.occurred_at,
      last_event_id: env.event_id
    }

    case Repo.get(PaymentSummary, env.aggregate_id) do
      nil ->
        %PaymentSummary{}
        |> PaymentSummary.upsert_changeset(attrs)
        |> Repo.insert(on_conflict: :nothing, conflict_target: :payment_id)
        |> to_ok()

      %PaymentSummary{aggregate_version: stored} when stored >= env.aggregate_version ->
        :ok

      summary ->
        summary |> PaymentSummary.upsert_changeset(attrs) |> Repo.update() |> to_ok()
    end
  end

  defp apply_event(%EventEnvelope{} = env) do
    case Repo.get(PaymentSummary, env.aggregate_id) do
      nil ->
        # payment.created not yet projected — snooze and retry
        {:snooze, 2}

      %PaymentSummary{aggregate_version: stored} when stored >= env.aggregate_version ->
        :ok

      summary ->
        summary
        |> PaymentSummary.upsert_changeset(state_attrs(env))
        |> Repo.update()
        |> to_ok()
    end
  end

  defp state_attrs(%EventEnvelope{} = env) do
    base = %{
      aggregate_version: env.aggregate_version,
      state: state_from_event(env.event_type),
      last_transition_at: env.occurred_at,
      last_event_id: env.event_id
    }

    Map.merge(base, extra_attrs(env))
  end

  defp state_from_event("payment.processing"), do: "processing"
  defp state_from_event("payment.authorised"), do: "authorised"
  defp state_from_event("payment.succeeded"), do: "succeeded"
  defp state_from_event("payment.failed"), do: "failed"
  defp state_from_event("payment.indeterminate"), do: "indeterminate"
  defp state_from_event("payment.disputed"), do: "disputed"
  defp state_from_event("payment.refunded"), do: "refunded"
  defp state_from_event(_), do: "unknown"

  defp extra_attrs(%EventEnvelope{event_type: "payment.succeeded"} = env) do
    %{
      provider_code: env.payload["provider_code"],
      net_amount: env.payload["net_amount"],
      platform_fee: env.payload["platform_fee"],
      provider_fee: env.payload["provider_fee"]
    }
  end

  defp extra_attrs(_env), do: %{}

  defp to_ok({:ok, _}), do: :ok
  defp to_ok({:error, _} = err), do: err
end
