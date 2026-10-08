defmodule YagyeCore.Compliance.AmlProvider do
  @moduledoc """
  Behaviour for AML/sanctions screening providers.

  Implementations: Stub (dev/test), ComplyAdvantage (prod).
  Configure via: config :yagye_core, :aml_provider, YagyeCore.Compliance.AmlProvider.Stub
  """

  @doc "Enrol a new subject for screening. Returns provider-assigned subject ID."
  @callback enrol(subject :: map()) ::
              {:ok, %{provider_id: String.t(), status: String.t()}} | {:error, term()}

  @doc "Refresh screening status for an existing subject."
  @callback refresh(provider_id :: String.t()) ::
              {:ok, %{status: String.t(), hits: [map()]}} | {:error, term()}

  @doc "Fetch detail for a specific screening hit by provider hit ID."
  @callback fetch_hit(provider_hit_id :: String.t()) :: {:ok, map()} | {:error, term()}

  def impl, do: Application.fetch_env!(:yagye_core, :aml_provider)
end
