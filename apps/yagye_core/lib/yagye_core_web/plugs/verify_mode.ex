defmodule YagyeCoreWeb.Plugs.VerifyMode do
  @moduledoc false

  # Confirms the merchant has been granted the mode their API key targets.
  # Simulation and sandbox are always enabled after registration.
  # Live mode requires an explicit approval grant in merchant_modes.
  #
  # Must run after Authenticate (requires conn.assigns.api_key).

  @behaviour Plug

  import Plug.Conn

  alias YagyeCore.Merchants

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{assigns: %{api_key: %{mode: mode}}} = conn, _opts)
      when mode in [:simulation, :sandbox],
      do: conn

  def call(%{assigns: %{api_key: %{mode: :live}, merchant_id: merchant_id}} = conn, _opts) do
    if Merchants.live_mode_enabled?(merchant_id) do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        403,
        Jason.encode!(%{
          error: %{
            code: "live_mode_not_enabled",
            message: "Live mode has not been enabled for this merchant"
          }
        })
      )
      |> halt()
    end
  end
end
