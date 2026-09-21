defmodule YagyeCore.Payments.ProviderAdapter do
  @moduledoc """
  Behaviour every payment provider adapter must implement.

  Adapters translate provider-specific vocabulary into the core's result types.
  The adapter for a payment is resolved from the provider's `adapter_module`
  database field — no global config, no case-on-provider-code in the domain.

  `name_enquiry` is an optional callback: only native-rail adapters (MoMo) need
  to implement it. External PSP adapters (Flutterwave, Paystack) may omit it.
  """

  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}
  alias YagyeCore.Providers.Schemas.Provider

  @type charge_ok :: %{
          provider_reference: String.t(),
          auth_code: String.t() | nil
        }

  @type charge_error :: %{
          error_class: :definite_failure | :retryable_error | :indeterminate,
          response_code: String.t() | nil,
          response_message: String.t() | nil
        }

  @type name_enquiry_ok :: %{
          account_name: String.t(),
          kyc_tier: String.t() | nil
        }

  @type disburse_ok :: %{provider_reference: String.t()}

  # credential is a plain map of decrypted fields, always including "base_url".
  # The adapter is responsible for extracting what it needs (api_key, secret, etc.).
  @callback charge(Payment.t(), PaymentAttempt.t(), credential :: map()) ::
              {:ok, charge_ok()} | {:error, charge_error()} | {:pending, map()}

  @callback query_charge(PaymentAttempt.t(), credential :: map()) ::
              {:ok, charge_ok()} | {:error, charge_error()}

  # Only native-rail adapters need this. External PSP adapters may omit it.
  @callback name_enquiry(opts :: %{msisdn: String.t(), network: String.t()}, credential :: map()) ::
              {:ok, name_enquiry_ok()} | {:error, map()}

  # Sends settlement funds to a merchant's mobile wallet.
  # Only native-rail adapters that support outbound disbursements implement this.
  # `params` must include: amount (integer, minor units), currency, reference (idempotency key),
  # recipient_msisdn (international format without leading +).
  @callback disburse(params :: map(), credential :: map()) ::
              {:ok, disburse_ok()} | {:pending, disburse_ok()} | {:error, map()}

  @optional_callbacks [name_enquiry: 2, disburse: 2]

  @doc """
  Returns the adapter module for a given provider.

  Resolution order:
  1. The simulator (code: "simulator") always uses the globally configured adapter
     so that Mox can replace it in tests.
  2. Any provider with adapter_module set in the DB uses that module — this
     covers both external PSPs and native rails like MTN MoMo.
  3. Anything else falls back to the globally configured adapter.
  """
  def for_provider(%Provider{code: "simulator"}), do: adapter()

  def for_provider(%Provider{adapter_module: mod}) when is_binary(mod) do
    # Elixir stores module atoms with the "Elixir." prefix internally.
    # The seeds store the human-readable name without it, so we add it here.
    String.to_existing_atom("Elixir." <> mod)
  rescue
    ArgumentError ->
      reraise "No compiled adapter module '#{mod}'. Check providers seed or migration.",
              __STACKTRACE__
  end

  def for_provider(_), do: adapter()

  @doc "Returns the globally configured adapter module (used for the simulator and as fallback)."
  def adapter do
    Application.fetch_env!(:yagye_core, :provider_adapter)
  end
end
