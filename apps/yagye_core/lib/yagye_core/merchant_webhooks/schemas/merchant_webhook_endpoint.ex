defmodule YagyeCore.MerchantWebhooks.Schemas.MerchantWebhookEndpoint do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "merchant_webhook_endpoints" do
    field :public_id, :string
    field :merchant_id, :binary_id
    field :mode, :string
    field :url, :string
    # AES-256-GCM encrypted HMAC signing secret; decrypted only at delivery time
    field :secret_encrypted, :binary
    field :subscribed_events, {:array, :string}, default: []
    field :active, :boolean, default: true
    field :consecutive_failures, :integer, default: 0
    field :disabled_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w[public_id merchant_id mode url secret_encrypted]a
  @optional ~w[subscribed_events active consecutive_failures disabled_at]a

  def changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:mode, ~w[live test])
    |> validate_format(:url, ~r/\Ahttps?:\/\//i, message: "must be a valid HTTP/S URL")
    |> unique_constraint(:public_id)
  end

  def disable_changeset(endpoint) do
    change(endpoint,
      active: false,
      disabled_at: DateTime.utc_now(),
      consecutive_failures: endpoint.consecutive_failures + 1
    )
  end

  def record_failure_changeset(endpoint) do
    change(endpoint, consecutive_failures: endpoint.consecutive_failures + 1)
  end

  def record_success_changeset(endpoint) do
    change(endpoint, consecutive_failures: 0)
  end
end
