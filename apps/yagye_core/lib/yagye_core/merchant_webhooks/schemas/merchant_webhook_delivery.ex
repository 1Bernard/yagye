defmodule YagyeCore.MerchantWebhooks.Schemas.MerchantWebhookDelivery do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_states ~w[pending delivering delivered failed exhausted]

  schema "merchant_webhook_deliveries" do
    field :endpoint_id, :binary_id
    field :event_id, :string
    field :event_type, :string
    field :attempt, :integer, default: 1
    field :state, :string, default: "pending"
    field :request_headers, :map, default: %{}
    field :request_body, :map, default: %{}
    field :response_status, :integer
    field :response_body, :string
    field :duration_ms, :integer
    field :next_attempt_at, :utc_datetime_usec
    field :delivered_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w[endpoint_id event_id event_type attempt state]a
  @optional ~w[request_headers request_body response_status response_body
               duration_ms next_attempt_at delivered_at]a

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:state, @valid_states)
    |> unique_constraint([:endpoint_id, :event_id, :attempt])
  end
end
