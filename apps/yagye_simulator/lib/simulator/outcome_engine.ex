defmodule Simulator.OutcomeEngine do
  @moduledoc """
  Determines charge and prompt outcomes from scenario rates and an optional seed.

  When a seed is provided the outcome is deterministic — same seed always produces
  the same sequence. This makes failing tests reproducible without needing to
  describe the exact sequence that triggered the failure.

  Without a seed a random value is used, which exercises the rate distribution
  across the full test suite without being tied to a specific run.
  """

  require OpenTelemetry.Tracer

  alias Simulator.Scenarios.Schemas.Scenario

  @type card_outcome :: :authorised | :declined | :timeout | :provider_error
  @type wallet_outcome :: :approved | :declined | :expired

  @spec card_outcome(Scenario.t() | nil, integer() | nil) :: card_outcome()
  def card_outcome(scenario, seed) do
    OpenTelemetry.Tracer.with_span "simulator.outcome_engine.card" do
      roll = roll(seed)
      scenario = scenario || defaults()

      decline = to_float(scenario.decline_rate)
      timeout = to_float(scenario.timeout_rate)
      error = to_float(scenario.provider_error_rate)

      outcome =
        cond do
          roll < decline -> :declined
          roll < decline + timeout -> :timeout
          roll < decline + timeout + error -> :provider_error
          true -> :authorised
        end

      OpenTelemetry.Tracer.set_attributes([{"outcome", Atom.to_string(outcome)}])
      outcome
    end
  end

  @spec wallet_outcome(Scenario.t() | nil, integer() | nil) :: wallet_outcome()
  def wallet_outcome(scenario, seed) do
    OpenTelemetry.Tracer.with_span "simulator.outcome_engine.wallet" do
      roll = roll(seed)
      scenario = scenario || defaults()

      decline = to_float(scenario.decline_rate)
      timeout = to_float(scenario.timeout_rate)

      outcome =
        cond do
          roll < decline -> :declined
          roll < decline + timeout -> :expired
          true -> :approved
        end

      OpenTelemetry.Tracer.set_attributes([{"outcome", Atom.to_string(outcome)}])
      outcome
    end
  end

  @spec name_enquiry_outcome(binary()) :: :found | :not_found
  def name_enquiry_outcome(msisdn) do
    # msisdn ending in 0 = NOT_FOUND scenario number; anything else = FOUND
    if String.ends_with?(msisdn, "0"), do: :not_found, else: :found
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp roll(nil) do
    :rand.uniform()
  end

  defp roll(seed) when is_integer(seed) do
    :rand.seed(:exsss, {seed, seed + 1, seed + 2})
    :rand.uniform()
  end

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(f) when is_float(f), do: f
  defp to_float(i) when is_integer(i), do: i / 1.0

  defp defaults do
    %{
      decline_rate: Decimal.new("0.050"),
      timeout_rate: Decimal.new("0.040"),
      provider_error_rate: Decimal.new("0.010")
    }
  end
end
