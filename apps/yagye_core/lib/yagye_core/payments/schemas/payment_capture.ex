defmodule YagyeCore.Payments.Schemas.PaymentCapture do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  @valid_states ~w[requested succeeded failed indeterminate]
  @valid_failure_codes ~w[exceeds_authorisation auth_expired already_final declined]

  schema "payment_captures" do
    field :public_id, :string
    field :payment_id, Uniq.UUID
    field :attempt_id, Uniq.UUID
    field :sequence, :integer
    field :amount, :integer
    field :currency, :string
    field :is_final, :boolean, default: false
    field :state, :string, default: "requested"
    field :provider_reference, :string
    field :arn, :string
    field :failure_code, :string
    field :idempotency_token, :string
    field :captured_at, :utc_datetime_usec

    timestamps(inserted_at: :inserted_at)
  end

  @required ~w[payment_id attempt_id sequence amount currency idempotency_token]a

  def changeset(capture, attrs) do
    capture
    |> cast(attrs, [
      :payment_id,
      :attempt_id,
      :sequence,
      :amount,
      :currency,
      :is_final,
      :state,
      :provider_reference,
      :arn,
      :failure_code,
      :idempotency_token,
      :captured_at
    ])
    |> validate_required(@required)
    |> validate_inclusion(:state, @valid_states)
    |> validate_inclusion(:failure_code, @valid_failure_codes, allow_nil: true)
    |> validate_length(:currency, is: 3)
    |> validate_number(:amount, greater_than: 0)
    |> validate_number(:sequence, greater_than: 0)
    |> put_public_id()
    |> unique_constraint(:public_id)
    |> unique_constraint([:payment_id, :sequence])
    |> foreign_key_constraint(:payment_id)
    |> foreign_key_constraint(:attempt_id)
  end

  def state_changeset(capture, new_state, extra \\ %{}) do
    capture
    |> cast(Map.put(extra, :state, new_state), [
      :state,
      :captured_at,
      :arn,
      :provider_reference,
      :failure_code
    ])
    |> validate_inclusion(:state, @valid_states)
  end

  defp put_public_id(changeset) do
    if get_field(changeset, :public_id) do
      changeset
    else
      put_change(changeset, :public_id, "cap_" <> Uniq.UUID.uuid7())
    end
  end
end
