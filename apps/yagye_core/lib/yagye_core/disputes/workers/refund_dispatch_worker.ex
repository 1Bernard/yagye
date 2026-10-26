defmodule YagyeCore.Disputes.Workers.RefundDispatchWorker do
  @moduledoc false

  use Oban.Worker, queue: :payments, max_attempts: 3

  require Logger

  import Ecto.Query

  alias YagyeCore.Disputes
  alias YagyeCore.Disputes.Schemas.Refund
  alias YagyeCore.Payments.Providers.ProviderAdapter
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}
  alias YagyeCore.Providers
  alias YagyeCore.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"refund_id" => refund_id},
        attempt: attempt,
        max_attempts: max_attempts
      }) do
    with {:ok, refund} <- Disputes.get_refund_by_id(refund_id),
         :ok <- validate_requestable(refund),
         {:ok, payment} <- {:ok, Repo.get!(Payment, refund.payment_id)},
         {:ok, pay_attempt} <- find_succeeded_attempt(refund.payment_id),
         {:ok, provider} <- Providers.get_provider(pay_attempt.provider_id),
         {:ok, credential} <-
           Providers.fetch_credential_for_status_check(
             provider.id,
             payment.merchant_id,
             payment.mode
           ) do
      adapter = ProviderAdapter.for_provider(provider)

      if function_exported?(adapter, :refund, 3) do
        dispatch_refund(adapter, pay_attempt, refund, credential, attempt, max_attempts)
      else
        Logger.warning(
          "#{inspect(adapter)} does not implement refund/3 — settling refund #{refund.id} optimistically"
        )

        Disputes.settle_refund(refund)
      end
    end
  end

  @terminal_codes ~w[wallet_closed msisdn_ported exceeds_network_limit]

  defp dispatch_refund(adapter, pay_attempt, refund, credential, attempt, max_attempts) do
    case adapter.refund(pay_attempt, refund.amount, credential) do
      {:ok, result} ->
        provider_ref = result[:provider_ref] || result[:transaction_id]
        Disputes.settle_refund(refund, provider_ref, result)

      {:error, %{error_class: :definite_failure} = err} ->
        reason = err[:response_code] || "provider_declined"
        Logger.warning("Refund #{refund.id} rejected by provider: #{reason}")
        Disputes.fail_refund(refund, reason)

      {:error, %{response_code: code}} when code in @terminal_codes ->
        Disputes.fail_refund(refund, code)

      {:error, err} ->
        on_refund_retry_error(refund, err, attempt, max_attempts)
    end
  end

  defp on_refund_retry_error(refund, err, attempt, max_attempts) do
    Logger.warning("Refund #{refund.id} dispatch error: #{inspect(err)}")

    if attempt >= max_attempts do
      Logger.error("Refund #{refund.id} exhausted all retries — marking failed")
      Disputes.fail_refund(refund, "dispatch_exhausted")
      :ok
    else
      {:error, :retryable}
    end
  end

  # Only dispatch refunds that are in requested state.
  # pending_approval refunds are blocked until ops approves them.
  defp validate_requestable(%Refund{state: "requested"}), do: :ok

  defp validate_requestable(%Refund{state: "pending_approval"}),
    do: {:error, :awaiting_approval}

  defp validate_requestable(%Refund{}), do: {:ok, :noop}

  defp find_succeeded_attempt(payment_id) do
    case Repo.one(
           from(a in PaymentAttempt,
             where: a.payment_id == ^payment_id and a.state == "succeeded",
             limit: 1
           )
         ) do
      nil -> {:error, :no_succeeded_attempt}
      attempt -> {:ok, attempt}
    end
  end
end
