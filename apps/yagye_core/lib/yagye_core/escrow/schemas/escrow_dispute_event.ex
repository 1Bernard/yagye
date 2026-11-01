defmodule YagyeCore.Escrow.Schemas.EscrowDisputeEvent do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Escrow.Schemas.EscrowHold
  alias YagyeCore.Merchants.Schemas.Merchant

  @valid_event_types ~w[dispute_opened evidence_submitted resolved_for_buyer
                        resolved_for_merchant escalated]

  @type t :: %__MODULE__{}

  schema "escrow_dispute_events" do
    field :public_id, :string
    field :event_type, :string
    field :actor, :string
    field :note, :string
    field :metadata, :map, default: %{}

    belongs_to :escrow_hold, EscrowHold
    belongs_to :merchant, Merchant

    timestamps(inserted_at: :inserted_at)
  end

  @required ~w[escrow_hold_id merchant_id event_type actor]a
  @optional ~w[note metadata]a

  def changeset(event, attrs) do
    event
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:event_type, @valid_event_types)
    |> put_public_id()
    |> unique_constraint(:public_id)
    |> foreign_key_constraint(:escrow_hold_id)
    |> foreign_key_constraint(:merchant_id)
  end

  defp put_public_id(%{data: %{public_id: nil}} = cs) do
    put_change(cs, :public_id, "ede_" <> Uniq.UUID.uuid7())
  end

  defp put_public_id(cs), do: cs
end
