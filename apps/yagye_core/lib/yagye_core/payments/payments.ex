defmodule YagyeCore.Payments do
  @moduledoc false

  import Ecto.Query

  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt, PaymentEvent}
  alias YagyeCore.Payments.Workers.PaymentDispatchWorker
  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Repo

  # ── Public API ───────────────────────────────────────────────────────────────

  def create_payment(merchant_id, attrs) do
    with {:ok, {payment, event}} <- insert_payment(merchant_id, attrs),
         {:ok, _job} <- PaymentDispatchWorker.new(%{payment_id: payment.id}) |> Oban.insert() do
      {:ok, {payment, event}}
    end
  end

  def dispatch_payment(payment_id) do
    Repo.transaction(fn ->
      with {:ok, payment} <- get_payment_by_id(payment_id),
           {:ok, payment, action} <- transition_to_processing(payment) do
        case action do
          :new ->
            case insert_event(payment, "payment.processing", "created", "processing") do
              {:ok, _} -> payment
              {:error, reason} -> Repo.rollback(reason)
            end

          :existing ->
            payment
        end
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
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
    Repo.transaction(fn ->
      now = DateTime.utc_now()

      with {:ok, _attempt} <-
             attempt
             |> PaymentAttempt.result_changeset(%{
               state: "succeeded",
               provider_reference: result.provider_reference,
               dispatched_at: now
             })
             |> Repo.update(),
           {:ok, payment} <- transition(payment, "authorised"),
           {:ok, _event} <- insert_event(payment, "payment.authorised", "processing", "authorised"),
           {:ok, payment} <- transition(payment, "succeeded"),
           {:ok, _event} <- insert_event(payment, "payment.succeeded", "authorised", "succeeded") do
        payment
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def handle_provider_response(payment, attempt, {:error, %{error_class: :definite_failure} = err}) do
    Repo.transaction(fn ->
      with {:ok, _attempt} <-
             attempt
             |> PaymentAttempt.result_changeset(%{
               state: "failed",
               error_class: Atom.to_string(err.error_class),
               response_code: err.response_code,
               response_message: err.response_message
             })
             |> Repo.update(),
           {:ok, payment} <- transition(payment, "failed"),
           {:ok, _event} <- insert_event(payment, "payment.failed", "processing", "failed") do
        payment
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, payment} -> {:ok, payment}
      error -> error
    end
  end

  def handle_provider_response(payment, attempt, {:error, %{error_class: :indeterminate} = err}) do
    Repo.transaction(fn ->
      with {:ok, _attempt} <-
             attempt
             |> PaymentAttempt.result_changeset(%{
               state: "timed_out",
               error_class: Atom.to_string(err.error_class),
               response_code: err.response_code
             })
             |> Repo.update(),
           {:ok, payment} <- transition(payment, "indeterminate"),
           {:ok, _event} <-
             insert_event(payment, "payment.indeterminate", "processing", "indeterminate") do
        payment
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, payment} -> {:ok, payment}
      error -> error
    end
  end

  def handle_provider_response(_payment, attempt, {:error, %{error_class: :retryable_error} = err}) do
    attempt
    |> PaymentAttempt.result_changeset(%{
      state: "failed",
      error_class: Atom.to_string(err.error_class),
      response_code: err.response_code
    })
    |> Repo.update()

    {:error, :retryable_error}
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
    Repo.transaction(fn ->
      with {:ok, merchant} <- resolve_merchant(merchant_id),
           attrs = Map.merge(attrs, %{merchant_id: merchant.id, mode: current_mode(merchant)}),
           {:ok, payment} <- %Payment{} |> Payment.changeset(attrs) |> Repo.insert(),
           {:ok, event} <- insert_event(payment, "payment.created", nil, "created") do
        {payment, event}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp transition_to_processing(%Payment{state: "processing"} = payment), do: {:ok, payment, :existing}

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

  defp get_payment_by_id(id) do
    case Repo.get(Payment, id) do
      nil -> {:error, :not_found}
      payment -> {:ok, payment}
    end
  end

  defp transition(payment, to_state) do
    payment |> Payment.transition_changeset(to_state) |> Repo.update()
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
      occurred_at: now,
      recorded_at: now
    })
    |> Repo.insert()
  end
end
