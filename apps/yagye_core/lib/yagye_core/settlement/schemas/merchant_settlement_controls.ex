defmodule YagyeCore.Settlement.Schemas.MerchantSettlementControls do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Merchants.Schemas.Merchant

  schema "merchant_settlement_controls" do
    field :approval_threshold, :integer
    field :approver_user_codes, {:array, :string}, default: []
    field :updated_by, :string

    belongs_to :merchant, Merchant

    timestamps(inserted_at: :inserted_at, updated_at: :updated_at)
  end

  def changeset(controls, attrs) do
    controls
    |> cast(attrs, [:merchant_id, :approval_threshold, :approver_user_codes, :updated_by])
    |> validate_required([:merchant_id, :updated_by])
    |> validate_number(:approval_threshold, greater_than_or_equal_to: 0)
    |> validate_approver_codes()
    |> foreign_key_constraint(:merchant_id)
    |> unique_constraint(:merchant_id)
  end

  defp validate_approver_codes(cs) do
    codes = get_field(cs, :approver_user_codes) || []

    if is_list(codes) and Enum.all?(codes, &is_binary/1) do
      cs
    else
      add_error(cs, :approver_user_codes, "must be a list of strings")
    end
  end
end
