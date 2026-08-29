defmodule YagyeCore.Merchants.Schemas.ApiKey do
  @moduledoc false
  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  schema "api_keys" do
    field :public_id, :string
    field :mode, YagyeCore.Shared.Types.YagyeMode
    field :kind, :string
    field :key_prefix, :string
    field :secret_hash, :string
    field :label, :string, default: ""
    field :scopes, {:array, :string}, default: []
    field :last_used_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :created_by, :string

    belongs_to :merchant, YagyeCore.Merchants.Schemas.Merchant

    timestamps()
  end

  @required ~w[public_id merchant_id mode kind key_prefix scopes]a
  @optional ~w[label secret_hash expires_at created_by]a

  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:kind, ["publishable", "secret"])
    |> unique_constraint(:public_id)
    |> unique_constraint([:merchant_id, :mode, :key_prefix])
    |> foreign_key_constraint(:merchant_id)
  end
end
