defmodule YagyeCoreWeb.Controllers.Internal.ActivityController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.{Activity, Merchants}
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  # GET /internal/merchants/:merchant_code/activity
  def index(conn, %{"merchant_code" => merchant_code} = params) do
    limit = parse_limit(params["limit"])
    before = parse_datetime(params["before"])
    domains = parse_domains(params["domains"])

    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, events} <-
           Activity.list_for_merchant(merchant.id, limit: limit, before: before, domains: domains) do
      has_more = length(events) == limit

      next_cursor =
        if has_more, do: events |> List.last() |> Map.get(:occurred_at) |> DateTime.to_iso8601()

      Response.ok(conn, %{
        data: Enum.map(events, &serialize/1),
        meta: %{has_more: has_more, next_cursor: next_cursor}
      })
    end
  end

  defp serialize(event) do
    %{
      domain: event.domain,
      event_type: event.event_type,
      resource_type: event.resource_type,
      resource_id: event.resource_id,
      resource_ref: event.resource_ref,
      occurred_at: DateTime.to_iso8601(event.occurred_at),
      metadata: event.metadata || %{}
    }
  end

  defp parse_limit(nil), do: 50

  defp parse_limit(str) do
    case Integer.parse(str) do
      {n, _} -> min(max(n, 1), 100)
      :error -> 50
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_domains(nil), do: ~w[payment settlement dispute refund]

  defp parse_domains(str) when is_binary(str) do
    valid = ~w[payment settlement dispute refund]
    parsed = str |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.filter(&(&1 in valid))
    if parsed == [], do: valid, else: parsed
  end

  defp parse_domains(_), do: ~w[payment settlement dispute refund]
end
