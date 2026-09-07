defmodule Simulator.Web.Controllers.RootController do
  use Phoenix.Controller, formats: [:html]

  def index(conn, _params) do
    redirect(conn, to: "/admin/scenarios")
  end
end
