defmodule YagyeCore.Payments.Schemas.Payment do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Merchants.Schemas.Merchant

  @valid_states ~w[created processing requires_action authorised succeeded failed cancelled indeterminate disputed refunded chargebacked]
  @valid_rails ~w[fiat_provider internal]
  @valid_modes ~w[simulation live]

  @type t :: %__MODULE__{}

  schema "payments" do
    field :public_id, :string
    field :mode, :string
    field :amount, :integer
    field :currency, :string
    field :state, :string, default: "created"
    field :rail, :string
    field :method, :string
    field :merchant_reference, :string
    field :description, :string
    field :version, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :merchant, Merchant

    timestamps()
  end

  def changeset(payment, attrs) do
    payment
    |> cast(attrs, [
      :merchant_id,
      :mode,
      :amount,
      :currency,
      :rail,
      :method,
      :merchant_reference,
      :description,
      :metadata
    ])
    |> validate_required([:merchant_id, :mode, :amount, :currency, :rail])
    |> validate_inclusion(:mode, @valid_modes)
    |> validate_inclusion(:rail, @valid_rails)
    |> validate_number(:amount, greater_than: 0)
    |> validate_length(:currency, is: 3)
    |> put_public_id()
    |> put_metadata_default()
    |> unique_constraint(:public_id)
    |> unique_constraint([:merchant_id, :merchant_reference])
    |> foreign_key_constraint(:merchant_id)
  end

  def transition_changeset(payment, to_state) when to_state in @valid_states do
    payment
    |> change(state: to_state)
    |> optimistic_lock(:version)
  end

  defp put_public_id(%{data: %{public_id: nil}} = changeset) do
    put_change(changeset, :public_id, "pay_" <> Uniq.UUID.uuid7())
  end

  defp put_public_id(changeset), do: changeset

  defp put_metadata_default(changeset) do
    case get_field(changeset, :metadata) do
      nil -> put_change(changeset, :metadata, %{})
      _ -> changeset
    end
  end
end
