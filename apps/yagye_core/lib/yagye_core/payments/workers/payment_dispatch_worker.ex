defmodule YagyeCore.Payments.Workers.PaymentDispatchWorker do
  @moduledoc false

  require OpenTelemetry.Tracer

  use Oban.Worker, queue: :payments, max_attempts: 3

  alias YagyeCore.Payments
  alias YagyeCore.Payments.Providers.ProviderAdapter
  alias YagyeCore.Providers
  alias YagyeCore.Routing.CircuitBreaker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payment_id" => payment_id}, attempt: job_attempt}) do
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
            Payments.handle_provider_response(payment, attempt, result)

          {:error, %{error_class: class}} = error
          when class in [:definite_failure, :retryable_error] ->
            CircuitBreaker.record_failure(provider.id)
            Payments.handle_provider_response(payment, attempt, error)

          other ->
            Payments.handle_provider_response(payment, attempt, other)
        end
      end
    end
  end

  # Returns a list of provider IDs that have already been attempted on this payment.
  # Called on retry (job_attempt > 1) so we can route around already-failed providers.
  # On the first attempt this is always empty.
  defp previously_attempted_providers(_payment_id, 1), do: []

  defp previously_attempted_providers(payment_id, _job_attempt) do
    Payments.attempted_provider_ids(payment_id)
  end
end
