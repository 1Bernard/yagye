defmodule YagyeCore.Reconciliation.SimulatorReport do
  @moduledoc """
  Fetches a settlement report from the simulator HTTP API.

  Calls GET {base_url}/settlement-reports?date={date} using the provider's
  platform credential, then maps the response to the shape `ingest_report/2`
  expects. The simulator applies scenario defects (fee drift, missing lines)
  server-side, so the right-side data reflects the same imperfections a real
  PSP settlement file would have.
  """

  alias YagyeCore.Providers

  @spec generate(binary(), String.t(), Date.t()) :: {:ok, map()} | {:error, term()}
  def generate(provider_id, mode, %Date{} = report_date) do
    with {:ok, credential} <- Providers.fetch_credential_for_status_check(provider_id, nil, mode) do
      fetch_report(provider_id, mode, report_date, credential)
    end
  end

  # ── Private ───────────────────────────────────────────────────────────────────

  defp fetch_report(provider_id, mode, report_date, credential) do
    base_url = credential["base_url"]
    api_key = credential["api_key"]
    url = "#{base_url}/settlement-reports?date=#{Date.to_iso8601(report_date)}"

    opts =
      [headers: [{"x-api-key", api_key}], receive_timeout: 15_000] ++
        Application.get_env(:yagye_core, :simulator_req_opts, [])

    case Req.get(url, opts) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, build_payload(provider_id, mode, report_date, body)}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:simulator_http_error, status, body}}

      {:error, reason} ->
        {:error, {:simulator_connection_error, reason}}
    end
  end

  defp build_payload(provider_id, mode, report_date, body) do
    currency = body["currency"] || "USD"
    lines = Enum.map(body["lines"] || [], &map_line(&1, currency))
    reported_total = body["net_minor"] || 0

    payload = %{
      provider_id: provider_id,
      mode: mode,
      report_date: report_date,
      source: "api",
      raw_uri: "sim://#{body["file_ref"]}",
      currency: currency,
      reported_total: reported_total,
      line_count: length(lines),
      lines: lines
    }

    checksum =
      payload
      |> Jason.encode!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    Map.put(payload, :checksum, checksum)
  end

  defp map_line(line, currency) do
    value_date =
      case Date.from_iso8601(line["value_date"] || "") do
        {:ok, d} -> d
        _ -> Date.utc_today()
      end

    occurred_at = DateTime.new!(value_date, ~T[00:00:00], "Etc/UTC")

    %{
      line_number: line["line_number"],
      provider_reference: line["charge_ref"],
      transaction_type: line["line_type"] || "CHARGE",
      gross_amount: line["gross_minor"],
      fee_amount: line["fee_minor"],
      net_amount: line["net_minor"],
      currency: currency,
      occurred_at: occurred_at,
      value_date: value_date,
      raw: %{
        "charge_ref" => line["charge_ref"],
        "line_type" => line["line_type"],
        "gross_minor" => line["gross_minor"],
        "fee_minor" => line["fee_minor"],
        "net_minor" => line["net_minor"]
      }
    }
  end
end
