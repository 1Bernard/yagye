defmodule YagyeCore.Payments.Schemas.MomoNetworkConfig do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @valid_reliability ~w[primary advisory]

  # network is a text PK, not a UUID
  @primary_key {:network, :string, []}
  @derive {Phoenix.Param, key: :network}

  schema "momo_network_config" do
    field :display_name, :string
    field :msisdn_prefixes, {:array, :string}
    field :prompt_timeout_seconds, :integer
    field :callback_reliability, :string
    field :poll_interval_seconds, :integer
    field :supports_name_enquiry, :boolean, default: false
    field :supports_reversal, :boolean, default: false
    field :customer_daily_limit, :integer
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :network,
      :display_name,
      :msisdn_prefixes,
      :prompt_timeout_seconds,
      :callback_reliability,
      :poll_interval_seconds,
      :supports_name_enquiry,
      :supports_reversal,
      :customer_daily_limit
    ])
    |> validate_required([
      :network,
      :display_name,
      :msisdn_prefixes,
      :prompt_timeout_seconds,
      :callback_reliability,
      :poll_interval_seconds
    ])
    |> validate_inclusion(:callback_reliability, @valid_reliability)
    |> validate_number(:prompt_timeout_seconds, greater_than: 0)
    |> validate_number(:poll_interval_seconds, greater_than: 0)
  end
end
