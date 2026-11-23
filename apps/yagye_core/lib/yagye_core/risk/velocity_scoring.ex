defmodule YagyeCore.Risk.VelocityScoring do
  @moduledoc false

  # Calls /score/velocity on the yagye_scoring service.
  # Returns {:ok, %{anomaly_score: float, is_anomaly: bool, model_version: string}}
  # or {:error, :scoring_unavailable}.
  #
  # Caller decides what to do with the result.  During shadow mode (velocity_ml_enabled=false)
  # the result is logged but not acted on — VelocityChecker's rule-based limits remain
  # the active gate.

  require Logger

  alias YagyeCore.Risk.ScoringClient

  @doc """
  Scores a pending payment for velocity / burst anomaly.

  `msisdn_hash` must already be the SHA-256 hash of the raw MSISDN — never the raw value.
  Returns `{:ok, result}` or `{:error, :scoring_unavailable}`.
  """
  def score(payment, msisdn_hash) do
    now = DateTime.utc_now()

    body = %{
      payment_id: to_string(payment.id || "pre_#{Uniq.UUID.uuid7()}"),
      msisdn_hash: msisdn_hash || "",
      merchant_id: to_string(payment.merchant_id),
      amount_minor: payment.amount || 0,
      payment_method: payment.method || "mobile_money",
      hour_of_day: now.hour,
      day_of_week: Date.day_of_week(now) - 1
    }

    case ScoringClient.post_raw("/score/velocity", body) do
      {:ok, resp} ->
        result = %{
          anomaly_score: Map.get(resp, :anomaly_score, 0.0),
          is_anomaly: Map.get(resp, :is_anomaly, false),
          model_version: Map.get(resp, :model_version, "unknown")
        }

        Logger.info(
          "velocity.scored",
          payment_id: body.payment_id,
          anomaly_score: result.anomaly_score,
          is_anomaly: result.is_anomaly,
          model_version: result.model_version
        )

        {:ok, result}

      {:error, :scoring_unavailable} = err ->
        err
    end
  end
end
