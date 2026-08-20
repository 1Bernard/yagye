defmodule YagyeCore.Payments.ProviderAdapter do
  @moduledoc """
  Behaviour every payment provider adapter must implement.

  Adapters translate provider-specific vocabulary into the core's result types.
  No `case provider do` in the domain — the adapter is resolved from config.
  """

  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}

  @type charge_ok :: %{
    provider_reference: String.t(),
    auth_code: String.t() | nil
  }

  @type charge_error :: %{
    error_class: :definite_failure | :retryable_error | :indeterminate,
    response_code: String.t() | nil,
    response_message: String.t() | nil
  }

  # credential is a plain map of decrypted fields, always including "base_url".
  # The adapter is responsible for extracting what it needs (api_key, secret, etc.).
  @callback charge(Payment.t(), PaymentAttempt.t(), credential :: map()) ::
    {:ok, charge_ok()} | {:error, charge_error()}

  @callback query_charge(PaymentAttempt.t(), credential :: map()) ::
    {:ok, charge_ok()} | {:error, charge_error()}

  @doc "Returns the configured adapter module."
  def adapter do
    Application.fetch_env!(:yagye_core, :provider_adapter)
  end
end
