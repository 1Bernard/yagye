defmodule YagyeCore.Payments.Workers.PaymentDispatchWorker do
  @moduledoc false

  require Logger
  require OpenTelemetry.Tracer

  use Oban.Worker, queue: :payments, max_attempts: 3

  alias YagyeCore.Payments
  alias YagyeCore.Payments.Providers.ProviderAdapter
  alias YagyeCore.Providers
  alias YagyeCore.Risk.ScoringClient
  alias YagyeCore.Risk.Workers.ProviderHealthWorker
  alias YagyeCore.Routing.CircuitBreaker

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"payment_id" => payment_id},
        attempt: job_attempt,
        max_attempts: max_attempts
      }) do
    OpenTelemetry.Tracer.with_span "payment.dispatch",
                                   %{
                                     attributes: %{
                                       "payment_id" => payment_id,
                                       "job_attempt" => job_attempt
                                     }
                                   } do
      # On retry attempts (job_attempt > 1), we pass previously-tried provider IDs
      # so the routing layer can skip them and try the next best option.
      # This gives us automatic fallback: attempt 1 → primary, attempt 2 → secondary, etc.
      excluded_provider_ids = previously_attempted_providers(payment_id, job_attempt)

      with {:ok, payment} <- Payments.dispatch_payment(payment_id),
           {:ok, {provider, credential, routing_meta}} <-
             Providers.get_provider_for_payment(payment, excluded_provider_ids),
           {:ok, attempt} <- Payments.create_attempt(payment, provider.id, routing_meta) do
        # Fire-and-forget routing scoring for shadow mode / logging
        maybe_score_routing_async(payment, provider)

        OpenTelemetry.Tracer.set_attributes(%{
          "routing.source" => to_string(routing_meta[:source]),
          "routing.rule_id" => to_string(routing_meta[:rule_id]),
          "provider.code" => provider.code
        })

        # Inject the preloaded provider struct into the attempt so that outbox event
        # payloads in Payments can access provider.code without an extra DB query.
        attempt = %{attempt | provider: provider}

        t0 = System.monotonic_time(:millisecond)
        result = ProviderAdapter.for_provider(provider).charge(payment, attempt, credential)
        latency_ms = System.monotonic_time(:millisecond) - t0
        attempt = %{attempt | latency_ms: latency_ms}

        case result do
          {:pending, pending_data} ->
            Payments.handle_pending_auth(payment, attempt, pending_data)

          {:ok, _} ->
            CircuitBreaker.record_success(provider.id)
            ProviderHealthWorker.update_one(provider.id, provider.code)
            Payments.handle_provider_response(payment, attempt, result)

          {:error, %{error_class: :retryable_error} = err} = error ->
            CircuitBreaker.record_failure(provider.id)
            ProviderHealthWorker.update_one(provider.id, provider.code)
            handle_retryable_error(payment, attempt, error, err, job_attempt, max_attempts)

          {:error, %{error_class: :definite_failure}} = error ->
            CircuitBreaker.record_failure(provider.id)
            ProviderHealthWorker.update_one(provider.id, provider.code)
            Payments.handle_provider_response(payment, attempt, error)

          other ->
            Payments.handle_provider_response(payment, attempt, other)
        end
      else
        {:error, :no_provider_available} = err ->
          if job_attempt > 1 do
            Payments.fail_payment_no_provider(payment_id)
          end

          err

        other ->
          other
      end
    end
  end

  # Returns a list of provider IDs that have already been attempted on this payment.
  # Called on retry (job_attempt > 1) so we can route around already-failed providers.
  # On the first attempt this is always empty.
  defp handle_retryable_error(payment, attempt, error, err, job_attempt, max_attempts) do
    if job_attempt >= max_attempts do
      Payments.fail_exhausted_retryable_payment(payment, attempt, err)
      {:error, :retryable_error}
    else
      Payments.handle_provider_response(payment, attempt, error)
    end
  end

  defp previously_attempted_providers(_payment_id, 1), do: []

  defp previously_attempted_providers(payment_id, _job_attempt) do
    Payments.attempted_provider_ids(payment_id)
  end

  # Calls /score/routing asynchronously in shadow mode.
  # Results are logged but not used for provider selection until rollout > 0.
  # When routing_ml_rollout_percent > 0, this switches to synchronous and the
  # hint is passed into the routing layer (P20+ step).
  defp maybe_score_routing_async(payment, provider) do
    cfg = Application.get_env(:yagye_core, :scoring)
    rollout = cfg[:routing_ml_rollout_percent]
    if rollout >= 0, do: Task.start(fn -> log_routing_score(payment, provider) end)
  end

  # The selected provider is sent as the single candidate (go/hold signal, Model A).
  # FastAPI's RoutingScoringRequest requires at least one candidate.
  defp log_routing_score(payment, provider) do
    case ScoringClient.score_routing(payment, [provider]) do
      {:ok, result} ->
        score =
          result[:provider_scores]
          |> List.wrap()
          |> List.first()
          |> case do
            %{"score" => s} -> s
            %{score: s} -> s
            _ -> nil
          end

        Logger.debug("scoring.routing.shadow",
          payment_id: payment.id,
          provider_code: provider.code,
          score: score,
          routing_mode: result[:routing_mode],
          model_version: result[:model_version]
        )

      {:error, :scoring_unavailable} ->
        :ok
    end
  end
end
