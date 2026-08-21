defmodule Simulator.Accounts.Schemas.ApiKey do
  @moduledoc false

  use Simulator.Schema
  import Ecto.Changeset

  alias Simulator.Accounts.Schemas.Account

  schema "gw_api_keys" do
    field :key_hash, :string
    field :label, :string
    field :active, :boolean, default: true
    field :revoked_at, :utc_datetime_usec

    belongs_to :account, Account

    field :created_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [:account_id, :key_hash, :label, :active, :revoked_at])
    |> validate_required([:account_id, :key_hash, :label])
    |> unique_constraint([:account_id, :key_hash])
    |> foreign_key_constraint(:account_id)
  end
end
