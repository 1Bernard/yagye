defmodule YagyeCore.Ledger.Schemas.Balance do
  @moduledoc false

  use Ecto.Schema

  @primary_key false
  schema "ledger_balances" do
    field :account_id, Ecto.UUID, primary_key: true
    field :balance, :integer
    field :last_posting_id, :integer
    field :updated_at, :utc_datetime_usec
  end
end
