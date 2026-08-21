defmodule YagyeCore.Payments.Schemas.PaymentAttempt do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  @valid_states ~w[created dispatched succeeded failed timed_out resolution_pending abandoned]

  @type t :: %__MODULE__{}

  schema "payment_attempts" do
    field :public_id, :string
    field :attempt_number, :integer
    field :method, :string
    field :state, :string, default: "created"
    field :provider_reference, :string
    field :idempotency_token, :string
    field :response_code, :string
    field :response_message, :string
    field :error_class, :string
    field :latency_ms, :integer
    field :dispatched_at, :utc_datetime_usec
    field :raw_response, :map

    belongs_to :payment, YagyeCore.Payments.Schemas.Payment
    belongs_to :provider, YagyeCore.Providers.Schemas.Provider

    timestamps(inserted_at: :inserted_at)
  end

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :payment_id,
      :provider_id,
      :attempt_number,
      :method,
      :state,
      :idempotency_token,
      :provider_reference,
      :response_code,
      :response_message,
      :error_class,
      :latency_ms,
      :dispatched_at,
      :raw_response
    ])
    |> validate_required([:payment_id, :provider_id, :attempt_number, :idempotency_token])
    |> validate_inclusion(:state, @valid_states)
    |> put_public_id()
    |> unique_constraint([:payment_id, :attempt_number])
    |> unique_constraint(:public_id)
    |> foreign_key_constraint(:payment_id)
    |> foreign_key_constraint(:provider_id)
  end

  defp put_public_id(%{data: %{public_id: nil}} = changeset) do
    put_change(changeset, :public_id, "att_" <> Uniq.UUID.uuid7())
  end

  defp put_public_id(changeset), do: changeset

  def result_changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :state,
      :provider_reference,
      :response_code,
      :response_message,
      :error_class,
      :latency_ms,
      :raw_response
    ])
    |> validate_inclusion(:state, @valid_states)
  end
end
