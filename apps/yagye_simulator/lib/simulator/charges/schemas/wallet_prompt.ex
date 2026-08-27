defmodule Simulator.Charges.Schemas.WalletPrompt do
  @moduledoc false

  use Simulator.Schema
  import Ecto.Changeset

  alias Simulator.Charges.Schemas.Charge

  @valid_networks ~w[MTN TELECEL AIRTELTIGO]
  @valid_states ~w[SENT APPROVED DECLINED EXPIRED]

  schema "gw_wallet_prompts" do
    field :network, :string
    field :msisdn, :string
    field :prompt_state, :string, default: "SENT"
    field :decline_code, :string
    field :approval_delay_ms, :integer, default: 3_000
    field :account_name, :string
    field :sent_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec

    belongs_to :charge, Charge
  end

  def changeset(prompt, attrs) do
    prompt
    |> cast(attrs, [
      :charge_id,
      :network,
      :msisdn,
      :prompt_state,
      :decline_code,
      :approval_delay_ms,
      :account_name,
      :sent_at,
      :resolved_at
    ])
    |> validate_required([:charge_id, :network, :msisdn, :approval_delay_ms])
    |> validate_inclusion(:network, @valid_networks)
    |> validate_inclusion(:prompt_state, @valid_states)
    |> foreign_key_constraint(:charge_id)
  end
end
