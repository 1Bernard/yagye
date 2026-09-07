defmodule YagyeCore.Payments.Workers.PaymentStatusCheckWorker do
  @moduledoc """
  Polls the provider for payments stuck in `requires_action`.

  Enqueued by `handle_pending_auth` after the payment enters `requires_action`.
  Runs every `poll_interval_seconds` (from `MomoNetworkConfig`) up to
  `@max_polls` times. On a definitive result it calls `handle_provider_response`
  to transition the payment; otherwise it reschedules itself.

  `PaymentTimeoutWorker` acts as the hard deadline and runs concurrently — if
  it fires and marks the payment failed first, this worker exits early (idempotent).
  """

  use Oban.Worker, queue: :payments, max_attempts: 1

  require Logger

  alias YagyeCore.Payments
  alias YagyeCore.Payments.ProviderAdapter
  alias YagyeCore.Payments.Schemas.{MomoNetworkConfig, PaymentAttempt}
  alias YagyeCore.Providers
  alias YagyeCore.Repo

  @max_polls 12
  @default_poll_interval_s 30

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "payment_id" => payment_id,
          "attempt_id" => attempt_id,
          "poll_number" => poll_number
        }
      }) do
    with {:ok, payment} <- Payments.get_payment_by_id(payment_id),
         {:requires_action, true} <- {:requires_action, payment.state == "requires_action"},
         {:ok, attempt} <- get_attempt(attempt_id),
         {:ok, {_provider, credential}} <- Providers.get_provider_for_payment(payment) do
      case ProviderAdapter.adapter().query_charge(attempt, credential) do
        {:ok, result} ->
          Payments.handle_provider_response(payment, attempt, {:ok, result})

        {:error, %{error_class: :definite_failure} = err} ->
          Payments.handle_provider_response(payment, attempt, {:error, err})

        _still_pending ->
          maybe_reschedule(payment_id, attempt_id, poll_number, payment)
      end
    else
      {:requires_action, false} ->
        :ok

      {:error, :not_found} ->
        Logger.warning("[PaymentStatusCheckWorker] payment or attempt not found",
          payment_id: payment_id,
          attempt_id: attempt_id
        )

        :ok

      {:error, reason} ->
        Logger.warning("[PaymentStatusCheckWorker] provider credential error",
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp get_attempt(attempt_id) do
    case Repo.get(PaymentAttempt, attempt_id) do
      nil -> {:error, :not_found}
      attempt -> {:ok, attempt}
    end
  end

  defp maybe_reschedule(payment_id, attempt_id, poll_number, payment) do
    if poll_number >= @max_polls do
      Logger.info("[PaymentStatusCheckWorker] max polls reached, leaving for recon",
        payment_id: payment_id
      )

      :ok
    else
      interval = poll_interval_for(payment)

      %{
        "payment_id" => payment_id,
        "attempt_id" => attempt_id,
        "poll_number" => poll_number + 1
      }
      |> __MODULE__.new(schedule_in: interval)
      |> Oban.insert()

      :ok
    end
  end

  defp poll_interval_for(payment) do
    network = get_in(payment.metadata, ["network"])

    case network && Repo.get(MomoNetworkConfig, network) do
      %MomoNetworkConfig{poll_interval_seconds: s} when is_integer(s) -> s
      _ -> @default_poll_interval_s
    end
  end
end
