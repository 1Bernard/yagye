defmodule YagyeCheckoutWeb.HealthController do
  use Phoenix.Controller, formats: [:html, :json]

  def check(conn, _params) do
    conn |> put_status(:ok) |> text("ok")
  end
end
