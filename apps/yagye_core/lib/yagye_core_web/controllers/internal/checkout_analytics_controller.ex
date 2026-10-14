defmodule YagyeCoreWeb.Controllers.Internal.CheckoutAnalyticsController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.CheckoutSessions
  alias YagyeCore.Merchants
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  # GET /internal/merchants/:merchant_code/checkout-analytics
  def show(conn, %{"merchant_code" => merchant_code} = params) do
    with {:ok, merchant} <- Merchants.get_merchant(merchant_code) do
      from_dt = parse_date(params["from"], days_ago: 30)
      to_dt = parse_date(params["to"], [])
      analytics = CheckoutSessions.analytics(merchant.id, from: from_dt, to: to_dt)
      Response.ok(conn, analytics)
    end
  end

  defp parse_date(nil, days_ago: n),
    do: DateTime.add(DateTime.utc_now(), -n * 86_400, :second)

  defp parse_date(nil, _), do: DateTime.utc_now()

  defp parse_date(str, _) do
    case Date.from_iso8601(str) do
      {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      _ -> DateTime.utc_now()
    end
  end
end
