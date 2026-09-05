defmodule YagyeCoreWeb.HealthController do
  use YagyeCoreWeb, :controller

  def check(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
