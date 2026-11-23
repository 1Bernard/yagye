defmodule YagyeCore.Reconciliation.ReconScoring do
  @moduledoc false

  # Calls /score/recon_break on the yagye_scoring service to auto-classify
  # a detected reconciliation break.
  #
  # This module is called from Reconciliation.auto_classify_break/1 when a
  # new break is detected. High-confidence classifications (>= 0.80) are
  # applied automatically to transition the break from "detected" → "triaged".
  # Lower-confidence results are stored as evidence on the break for human review.

  require Logger

  alias YagyeCore.Risk.ScoringClient

  @auto_classify_threshold 0.80

  @doc """
  Scores a ReconciliationBreak and returns `{:ok, result}` or `{:error, reason}`.

  `result` is `%{classification: string, confidence: float, model_version: string}`.
  """
  def score(break) do
    age_hours =
      DateTime.diff(DateTime.utc_now(), to_utc(break.detected_at), :second) / 3600.0

    body = %{
      break_id: break.public_id,
      amount_delta_minor: break.difference || 0,
      expected_amount: break.expected_amount || 0,
      age_hours: Float.round(age_hours, 2),
      has_right_ref: not is_nil(break.right_ref),
      settlement_offset_days: 0
    }

    case ScoringClient.post_raw("/score/recon_break", body) do
      {:ok, resp} ->
        result = %{
          classification: resp[:classification] || "unknown",
          confidence: resp[:confidence] || 0.0,
          model_version: resp[:model_version] || "unknown"
        }

        Logger.info(
          "recon_break.scored",
          break_id: break.public_id,
          classification: result.classification,
          confidence: result.confidence,
          model_version: result.model_version
        )

        {:ok, result}

      {:error, :scoring_unavailable} = err ->
        err
    end
  end

  @doc """
  Returns true when a scoring result is confident enough to auto-classify.
  """
  def auto_classify?(result), do: result.confidence >= @auto_classify_threshold

  # ── Private ──────────────────────────────────────────────────────────────────

  defp to_utc(%DateTime{} = dt), do: dt
  defp to_utc(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")
end
