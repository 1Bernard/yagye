defmodule YagyeCore.Repo do
  use Ecto.Repo,
    otp_app: :yagye_core,
    adapter: Ecto.Adapters.Postgres
end
