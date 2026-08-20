defmodule YagyeCore.Ledger.Schemas.Posting do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @valid_directions ~w[debit credit]

  schema "ledger_postings" do
    field :direction, :string
    field :amount, :integer
    field :currency, :string
    field :merchant_id, Ecto.UUID

    belongs_to :entry, YagyeCore.Ledger.Schemas.Entry, type: Ecto.UUID
    belongs_to :account, YagyeCore.Ledger.Schemas.Account, type: Ecto.UUID

    timestamps(inserted_at: :inserted_at, updated_at: false)
  end

  def changeset(posting, attrs) do
    posting
    |> cast(attrs, [:entry_id, :account_id, :direction, :amount, :currency, :merchant_id])
    |> validate_required([:entry_id, :account_id, :direction, :amount, :currency])
    |> validate_inclusion(:direction, @valid_directions)
    |> validate_number(:amount, greater_than: 0)
    |> validate_length(:currency, is: 3)
    |> foreign_key_constraint(:entry_id)
    |> foreign_key_constraint(:account_id)
  end
end
