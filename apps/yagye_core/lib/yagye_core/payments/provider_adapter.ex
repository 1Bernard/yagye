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

  # credential is a plain map of decrypted fields, always including "base_url".
  # The adapter is responsible for extracting what it needs (api_key, secret, etc.).
  @callback charge(Payment.t(), PaymentAttempt.t(), credential :: map()) ::
              {:ok, charge_ok()} | {:error, charge_error()} | {:pending, map()}

  @callback query_charge(PaymentAttempt.t(), credential :: map()) ::
              {:ok, charge_ok()} | {:error, charge_error()}

  # Only native-rail adapters need this. External PSP adapters may omit it.
  @callback name_enquiry(opts :: %{msisdn: String.t(), network: String.t()}, credential :: map()) ::
              {:ok, name_enquiry_ok()} | {:error, map()}

  @optional_callbacks [name_enquiry: 2]

  @doc """
  Returns the adapter module for a given provider.

  For external PSPs: reads `provider.adapter_module` (module name stored as a
  string in the DB, without the `Elixir.` prefix) and resolves it to a module
  atom. Raises if the module is not compiled — always a configuration bug.

  For the simulator: falls through to `adapter/0` so the globally configured
  adapter (the Mox mock in tests) is respected.
  """
  def for_provider(%Provider{kind: "native_rail"}), do: adapter()
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

  @doc "Returns the globally configured adapter module (used for native rails and simulator)."
  def adapter do
    Application.fetch_env!(:yagye_core, :provider_adapter)
  end
end
