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

  @callback charge(Payment.t(), PaymentAttempt.t()) ::
    {:ok, charge_ok()} | {:error, charge_error()}

  @callback query_charge(PaymentAttempt.t()) ::
    {:ok, charge_ok()} | {:error, charge_error()}

  @doc "Returns the configured adapter module."
  def adapter do
    Application.fetch_env!(:yagye_core, :provider_adapter)
  end
end
