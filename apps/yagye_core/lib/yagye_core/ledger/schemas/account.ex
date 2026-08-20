defmodule YagyeCore.Ledger.Schemas.Account do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  @valid_normal_balances ~w[debit credit]
  @valid_scope_types ~w[merchant provider platform]
  @valid_modes ~w[simulation sandbox live]

  schema "ledger_accounts" do
    field :code, :string
    field :account_type, :string
    field :normal_balance, :string
    field :scope_type, :string
    field :scope_id, Ecto.UUID
    field :currency, :string
    field :mode, :string
    field :allows_negative, :boolean, default: false

    timestamps(inserted_at: :inserted_at, updated_at: false)
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [
      :code,
      :account_type,
      :normal_balance,
      :scope_type,
      :scope_id,
      :currency,
      :mode,
      :allows_negative
    ])
    |> validate_required([:code, :account_type, :normal_balance, :scope_type, :currency, :mode])
    |> validate_inclusion(:normal_balance, @valid_normal_balances)
    |> validate_inclusion(:scope_type, @valid_scope_types)
    |> validate_inclusion(:mode, @valid_modes)
    |> validate_length(:currency, is: 3)
    |> unique_constraint(:code)
  end
end
