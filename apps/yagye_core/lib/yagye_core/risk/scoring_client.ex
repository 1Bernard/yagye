defmodule YagyeCore.Risk.ScoringClient do
  @moduledoc false

  # HTTP client for the yagye_scoring FastAPI service.
  # 200ms hard timeout — a slow or unavailable scoring service must never
  # block the payment path. Both /score/risk and /score/routing return
  # {:ok, response} | {:error, :scoring_unavailable}.
  #
  # Shadow mode (risk_ml_enabled=false, routing_ml_rollout_percent=0) means
  # the call is made and logged but the result is not used for decisions.

  require Logger

  @doc """
  Calls /score/risk for transaction risk assessment.
  Returns {:ok, %{decision: "allow"|"review"|"block", score: float, reasons: list}}
  or {:error, :scoring_unavailable}.

  The request body mirrors `RiskScoringRequest` in
  apps/yagye_scoring/src/yagye_scoring/schemas/risk.py — keep the two in sync.
  """
  def score_risk(payment, merchant) do
    now = DateTime.utc_now()
    metadata = payment.metadata || %{}

    body = %{
      # Inline scoring happens before the payment row exists, so id may be nil.
      payment_id: to_string(payment.id || "pre_#{Uniq.UUID.uuid7()}"),
      merchant_id: to_string(merchant.id),
      customer_msisdn_hash: metadata["msisdn_hash"] || "",
      amount_minor: payment.amount || 0,
      hour_of_day: now.hour,
      day_of_week: Date.day_of_week(now) - 1,
      customer_kyc_tier: metadata["customer_kyc_tier"] || 1,
      is_new_customer: is_nil(payment.customer_id),
      is_new_msisdn_for_merchant: false,
      # Informational fields — ignored by the Pydantic model, kept for logging.
      currency: payment.currency,
      method: payment.method,
      mode: payment.mode
    }

    with {:ok, resp} <- post("/score/risk", body) do
      {:ok, normalise_risk(resp)}
    end
  end

  @doc """
  Calls /score/routing to rank providers by expected success probability.
  Returns {:ok, %{ranking: list, routing_mode: string}}
  or {:error, :scoring_unavailable}.

  The request body mirrors `RoutingScoringRequest` in
  apps/yagye_scoring/src/yagye_scoring/schemas/routing.py — keep the two in sync.
  """
  def score_routing(payment, provider_candidates) do
    now = DateTime.utc_now()

    body = %{
      payment_id: to_string(payment.id),
      provider_candidates:
        Enum.map(provider_candidates, fn p ->
          %{provider_code: p.code, provider_kind: Map.get(p, :kind) || "native_rail"}
        end),
      payment_method: payment.method,
      network_code: get_in(payment.metadata || %{}, ["network"]),
      amount_minor: payment.amount || 0,
      hour_of_day: now.hour,
      day_of_week: Date.day_of_week(now) - 1
    }

    with {:ok, resp} <- post("/score/routing", body) do
      {:ok, normalise_routing(resp)}
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  # FastAPI returns `risk_score`; Core callers historically read `score`.
  defp normalise_risk(%{risk_score: s} = resp) when not is_map_key(resp, :score),
    do: Map.put(resp, :score, s)

  defp normalise_risk(resp), do: resp

  # FastAPI returns `provider_scores` (sorted desc); expose `ranking` as provider codes.
  defp normalise_routing(%{provider_scores: scores} = resp)
       when is_list(scores) and not is_map_key(resp, :ranking) do
    Map.put(resp, :ranking, Enum.map(scores, &(&1["provider_code"] || &1[:provider_code])))
  end

  defp normalise_routing(resp), do: resp

  defp extra_req_opts, do: Application.get_env(:yagye_core, :scoring_req_opts, [])

  defp post(path, body) do
    cfg = Application.get_env(:yagye_core, :scoring)
    url = cfg[:service_url] <> path
    timeout = cfg[:timeout_ms]
    opts = [json: body, receive_timeout: timeout, retry: false] ++ extra_req_opts()

    case Req.post(url, opts) do
      {:ok, %Req.Response{status: 200, body: resp_body}} ->
        {:ok, atomize_keys(resp_body)}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("scoring.http_error", path: path, status: status)
        {:error, :scoring_unavailable}

      {:error, reason} ->
        Logger.warning("scoring.unavailable", path: path, reason: inspect(reason))
        {:error, :scoring_unavailable}
    end
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {String.to_atom(k), v} end)
  rescue
    _ -> map
  end

  defp atomize_keys(other), do: other
end
