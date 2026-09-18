defmodule YagyeCoreWeb.Controllers.Fx.FxRateController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.FX
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  @pairs [{"GHS", "USD"}, {"GHS", "EUR"}, {"GHS", "GBP"}]

  def index(conn, _params) do
    rates =
      Enum.flat_map(@pairs, fn {base, quote} ->
        case FX.get_rate(base, quote) do
          {:ok, rate} ->
            [
              %{
                base: rate.base,
                quote: rate.quote,
                rate: rate.rate,
                source: rate.source,
                quoted_at: rate.quoted_at,
                expires_at: rate.expires_at
              }
            ]

          {:error, :not_found} ->
            []
        end
      end)

    Response.ok(conn, %{object: "list", data: rates})
  end
end
