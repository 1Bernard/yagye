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
  """
  def score_risk(payment, merchant) do
    body = %{
      payment_id: payment.id,
      merchant_id: merchant.id,
      amount_minor: payment.amount,
      currency: payment.currency,
      method: payment.method,
      mode: payment.mode,
      msisdn_hash: get_in(payment.metadata, ["msisdn_hash"]),
      customer_id: payment.customer_id
    }

    post("/score/risk", body)
  end

  @doc """
  Calls /score/routing to rank providers by expected success probability.
  Returns {:ok, %{ranking: list, routing_mode: string}}
  or {:error, :scoring_unavailable}.
  """
  def score_routing(payment, provider_candidates) do
    body = %{
      payment_id: payment.id,
      amount_minor: payment.amount,
      currency: payment.currency,
      method: payment.method,
      mode: payment.mode,
      provider_codes: Enum.map(provider_candidates, & &1.code)
    }

    post("/score/routing", body)
  end

  # ── Private ──────────────────────────────────────────────────────────────────

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
