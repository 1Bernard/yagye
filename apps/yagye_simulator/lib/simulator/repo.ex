defmodule Simulator.Repo do
  use Ecto.Repo,
    otp_app: :simulator,
    adapter: Ecto.Adapters.Postgres
end
