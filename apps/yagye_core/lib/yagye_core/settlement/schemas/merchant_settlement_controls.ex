defmodule YagyeCore.Settlement.Schemas.MerchantSettlementControls do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Merchants.Schemas.Merchant

  @valid_frequencies ~w[daily weekly monthly]

  schema "merchant_settlement_controls" do
    field :approval_threshold, :integer
    field :approver_user_codes, {:array, :string}, default: []
    field :settlement_msisdn, :string
    field :settlement_bank_code, :string
    field :settlement_account_number, :string
    field :settlement_account_name, :string
    field :updated_by, :string

    # Settlement policy
    field :settlement_delay_days, :integer, default: 0
    field :minimum_payout_pesewas, :integer, default: 5_000
    field :settlement_frequency, :string, default: "daily"
    field :reserve_rate_bps, :integer, default: 0
    field :reserve_release_days, :integer, default: 90
    field :early_settlement_enabled, :boolean, default: false
    field :on_hold, :boolean, default: false
    field :hold_reason, :string

    belongs_to :merchant, Merchant

    timestamps(inserted_at: :inserted_at, updated_at: :updated_at)
  end

  def changeset(controls, attrs) do
    controls
    |> cast(attrs, [
      :merchant_id,
      :approval_threshold,
      :approver_user_codes,
      :settlement_msisdn,
      :settlement_bank_code,
      :settlement_account_number,
      :settlement_account_name,
      :updated_by,
      :settlement_delay_days,
      :minimum_payout_pesewas,
      :settlement_frequency,
      :reserve_rate_bps,
      :reserve_release_days,
      :early_settlement_enabled,
      :on_hold,
      :hold_reason
    ])
    |> validate_required([:merchant_id, :updated_by])
    |> validate_number(:approval_threshold, greater_than_or_equal_to: 0)
    |> validate_number(:settlement_delay_days,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 7
    )
    |> validate_number(:minimum_payout_pesewas, greater_than_or_equal_to: 0)
    |> validate_inclusion(:settlement_frequency, @valid_frequencies)
    |> validate_number(:reserve_rate_bps,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 2500
    )
    |> validate_number(:reserve_release_days,
      greater_than_or_equal_to: 30,
      less_than_or_equal_to: 365
    )
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
