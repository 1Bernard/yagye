defmodule YagyeCore.Escrow.Schemas.EscrowHold do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.PaymentLinks.Schemas.PaymentLink
  alias YagyeCore.Payments.Schemas.Payment

  @valid_states ~w[held disputed released refunded]

  @type t :: %__MODULE__{}

  schema "escrow_holds" do
    field :public_id, :string
    field :amount, :integer
    field :currency, :string
    field :mode, :string
    field :state, :string, default: "held"
    field :buyer_confirmed_at, :utc_datetime_usec
    field :auto_release_at, :utc_datetime_usec
    field :dispute_window_ends_at, :utc_datetime_usec
    field :released_at, :utc_datetime_usec
    field :refunded_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :payment, Payment
    belongs_to :payment_link, PaymentLink
    belongs_to :merchant, Merchant

    timestamps(inserted_at: :inserted_at)
  end

  @required ~w[payment_id payment_link_id merchant_id amount currency mode
               auto_release_at dispute_window_ends_at]a
  @optional ~w[buyer_confirmed_at released_at refunded_at metadata]a

  def changeset(hold, attrs) do
    hold
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:mode, ~w[simulation sandbox live])
    |> validate_number(:amount, greater_than: 0)
    |> validate_length(:currency, is: 3)
    |> put_public_id()
    |> unique_constraint(:public_id)
    |> unique_constraint(:payment_id)
    |> foreign_key_constraint(:payment_id)
    |> foreign_key_constraint(:payment_link_id)
    |> foreign_key_constraint(:merchant_id)
  end

  def transition_changeset(hold, to_state) when to_state in @valid_states do
    change(hold, state: to_state)
  end

  defp put_public_id(%{data: %{public_id: nil}} = cs) do
    put_change(cs, :public_id, "esh_" <> Uniq.UUID.uuid7())
  end

  defp put_public_id(cs), do: cs
end
