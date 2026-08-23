defmodule YagyeCore.Payments do
  @moduledoc false

  require OpenTelemetry.Tracer

  import Ecto.Query

  alias Ecto.Multi
  alias YagyeCore.Ledger
  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Outbox
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt, PaymentEvent}
  alias YagyeCore.Payments.Workers.PaymentDispatchWorker
  alias YagyeCore.Repo

  # ── Public API ───────────────────────────────────────────────────────────────

  def create_payment(merchant_id, attrs) do
    with {:ok, {payment, event}} <- insert_payment(merchant_id, attrs),
         {:ok, _job} <- PaymentDispatchWorker.new(%{payment_id: payment.id}) |> Oban.insert() do
      {:ok, {payment, event}}
    end
  end

  def dispatch_payment(payment_id) do
    Multi.new()
    |> Multi.run(:payment, fn _repo, _changes ->
      get_payment_by_id(payment_id)
    end)
    |> Multi.run(:transition, fn _repo, %{payment: payment} ->
      case transition_to_processing(payment) do
        {:ok, p, action} -> {:ok, {p, action}}
        error -> error
      end
    end)
    |> Multi.run(:event, fn _repo, %{transition: {payment, action}} ->
      case action do
        :existing -> {:ok, nil}
        :new -> insert_event(payment, "payment.processing", "created", "processing")
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{transition: {payment, _action}}} -> {:ok, payment}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def create_attempt(payment, provider_id) do
    attempt_number = next_attempt_number(payment.id)

    %PaymentAttempt{}
    |> PaymentAttempt.changeset(%{
      payment_id: payment.id,
      provider_id: provider_id,
      attempt_number: attempt_number,
      method: payment.method,
      idempotency_token: Uniq.UUID.uuid7()
    })
    |> Repo.insert()
  end

  def handle_provider_response(payment, attempt, {:ok, result}) do
    Multi.new()
    |> Multi.update(
      :attempt,
      PaymentAttempt.result_changeset(attempt, %{
        state: "succeeded",
        provider_reference: result.provider_reference,
        dispatched_at: DateTime.utc_now()
      })
    )
    |> Multi.update(:authorised, Payment.transition_changeset(payment, "authorised"))
    |> Multi.run(:authorised_event, fn _repo, %{authorised: p} ->
      insert_event(p, "payment.authorised", "processing", "authorised")
    end)
    |> Multi.insert(:authorised_outbox, fn %{authorised: p} ->
      Outbox.build_changeset(p, "payment.authorised", %{})
    end)
    |> Multi.update(:succeeded, fn %{authorised: p} ->
      Payment.transition_changeset(p, "succeeded")
    end)
    |> Multi.run(:succeeded_event, fn _repo, %{succeeded: p} ->
      insert_event(p, "payment.succeeded", "authorised", "succeeded")
    end)
    |> Multi.insert(:succeeded_outbox, fn %{succeeded: p} ->
      Outbox.build_changeset(p, "payment.succeeded", %{
        provider_code: result[:provider_code],
        amount: p.amount,
        currency: p.currency,
        net_amount: p.amount
      })
    end)
    |> Multi.run(:ledger, fn _repo, %{succeeded: p} ->
      Ledger.post_payment_settled(p, attempt)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{succeeded: payment}} -> {:ok, payment}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def handle_provider_response(
        payment,
        attempt,
        {:error, %{error_class: :definite_failure} = err}
      ) do
    Multi.new()
    |> Multi.update(
      :attempt,
      PaymentAttempt.result_changeset(attempt, %{
        state: "failed",
        error_class: Atom.to_string(err.error_class),
        response_code: err.response_code,
        response_message: err.response_message
      })
    )
    |> Multi.update(:payment, Payment.transition_changeset(payment, "failed"))
    |> Multi.run(:event, fn _repo, %{payment: p} ->
      insert_event(p, "payment.failed", "processing", "failed")
    end)
    |> Multi.insert(:outbox, fn %{payment: p} ->
      Outbox.build_changeset(p, "payment.failed", %{
        error_class: Atom.to_string(err.error_class),
        response_code: err.response_code,
        currency: p.currency
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{payment: payment}} -> {:ok, payment}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def handle_provider_response(payment, attempt, {:error, %{error_class: :indeterminate} = err}) do
    Multi.new()
    |> Multi.update(
      :attempt,
      PaymentAttempt.result_changeset(attempt, %{
        state: "timed_out",
        error_class: Atom.to_string(err.error_class),
        response_code: err.response_code
      })
    )
    |> Multi.update(:payment, Payment.transition_changeset(payment, "indeterminate"))
    |> Multi.run(:event, fn _repo, %{payment: p} ->
      insert_event(p, "payment.indeterminate", "processing", "indeterminate")
    end)
    |> Multi.insert(:outbox, fn %{payment: p} ->
      Outbox.build_changeset(p, "payment.indeterminate", %{
        response_code: err.response_code,
        currency: p.currency
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{payment: payment}} -> {:ok, payment}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def handle_provider_response(
        _payment,
        attempt,
        {:error, %{error_class: :retryable_error} = err}
      ) do
    attempt
    |> PaymentAttempt.result_changeset(%{
      state: "failed",
      error_class: Atom.to_string(err.error_class),
      response_code: err.response_code
    })
    |> Repo.update()

    {:error, :retryable_error}
  end

  def handle_pending_auth(payment, attempt, %{provider_reference: charge_ref}) do
    attempt_cs =
      attempt
      |> PaymentAttempt.result_changeset(%{state: "dispatched", provider_reference: charge_ref})
      |> Ecto.Changeset.put_change(:dispatched_at, DateTime.utc_now())

    Multi.new()
    |> Multi.update(:attempt, attempt_cs)
    |> Multi.update(:payment, Payment.transition_changeset(payment, "requires_action"))
    |> Multi.run(:event, fn _repo, %{payment: p} ->
      insert_event(p, "payment.requires_action", "processing", "requires_action")
    end)
    |> Multi.insert(:outbox, fn %{payment: p} ->
      Outbox.build_changeset(p, "payment.requires_action", %{
        method: p.method,
        amount: p.amount,
        currency: p.currency
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{payment: payment}} -> {:ok, payment}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def get_attempt_by_provider_ref(provider_reference) do
    case Repo.get_by(PaymentAttempt, provider_reference: provider_reference) do
      nil -> {:error, :not_found}
      attempt -> {:ok, attempt}
    end
  end

  def get_payment_by_id(id) do
    case Repo.get(Payment, id) do
      nil -> {:error, :not_found}
      payment -> {:ok, payment}
    end
  end

  def get_payment(public_id) do
    case Repo.get_by(Payment, public_id: public_id) do
      nil -> {:error, :not_found}
      payment -> {:ok, payment}
    end
  end

  def list_events(payment_id) do
    events =
      from(e in PaymentEvent,
        where: e.payment_id == ^payment_id,
        order_by: [asc: e.version]
      )
      |> Repo.all()

    {:ok, events}
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp insert_payment(merchant_id, attrs) do
    Multi.new()
    |> Multi.run(:merchant, fn _repo, _changes ->
      resolve_merchant(merchant_id)
    end)
    |> Multi.insert(:payment, fn %{merchant: merchant} ->
      merged = Map.merge(attrs, %{merchant_id: merchant.id, mode: current_mode(merchant)})
      Payment.changeset(%Payment{}, merged)
    end)
    |> Multi.run(:event, fn _repo, %{payment: p} ->
      insert_event(p, "payment.created", nil, "created")
    end)
    |> Multi.insert(:outbox, fn %{payment: p} ->
      Outbox.build_changeset(p, "payment.created", %{
        method: p.method,
        amount: p.amount,
        currency: p.currency,
        merchant_reference: p.merchant_reference,
        customer_reference: Map.get(attrs, :customer_reference)
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{payment: payment, event: event}} -> {:ok, {payment, event}}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp transition_to_processing(%Payment{state: "processing"} = payment),
    do: {:ok, payment, :existing}

  defp transition_to_processing(%Payment{state: "created"} = payment) do
    case payment |> Payment.transition_changeset("processing") |> Repo.update() do
      {:ok, payment} -> {:ok, payment, :new}
      error -> error
    end
  end

  defp transition_to_processing(%Payment{state: state}), do: {:error, {:invalid_state, state}}

  defp next_attempt_number(payment_id) do
    count =
      from(a in PaymentAttempt, where: a.payment_id == ^payment_id, select: count())
      |> Repo.one()

    count + 1
  end

  defp resolve_merchant(merchant_id) do
    case Repo.get(Merchant, merchant_id) do
      nil -> {:error, :not_found}
      merchant -> {:ok, merchant}
    end
  end

  defp current_mode(merchant) do
    case YagyeCore.Merchants.live_mode_enabled?(merchant.id) do
      true -> "live"
      false -> "simulation"
    end
  end

  defp insert_event(payment, event_type, from_state, to_state) do
    now = DateTime.utc_now()

    %PaymentEvent{}
    |> PaymentEvent.changeset(%{
      payment_id: payment.id,
      version: payment.version,
      event_type: event_type,
      from_state: from_state,
      to_state: to_state,
      actor: "system",
      correlation_id: payment.public_id,
      trace_id: current_trace_id(),
      occurred_at: now,
      recorded_at: now
    })
    |> Repo.insert()
  end

  defp current_trace_id do
    case OpenTelemetry.Tracer.current_span_ctx() do
      :undefined ->
        nil

      span_ctx ->
        trace_id = :otel_span.trace_id(span_ctx)

        if trace_id == 0,
          do: nil,
          else:
            trace_id |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")
    end
  end
end
