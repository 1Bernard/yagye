defmodule YagyeCore.Payments.Schemas.CardDecline do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:attempt_id, Uniq.UUID, autogenerate: false}
  @foreign_key_type Uniq.UUID

  @valid_hardness ~w[soft hard]
  @valid_origins ~w[issuer network gateway risk]

  # retry_after stored as integer seconds; Postgres interval maps awkwardly in Ecto.
  schema "card_declines" do
    field :raw_code, :string
    field :canonical_code, :string
    field :hardness, :string
    field :retryable, :boolean
    field :retry_after, :integer
    field :origin, :string
    field :customer_message_key, :string
  end

  @required ~w[attempt_id raw_code canonical_code hardness retryable origin customer_message_key]a

  def changeset(decline, attrs) do
    decline
    |> cast(attrs, [
      :attempt_id,
      :raw_code,
      :canonical_code,
      :hardness,
      :retryable,
      :retry_after,
      :origin,
      :customer_message_key
    ])
    |> validate_required(@required)
    |> validate_inclusion(:hardness, @valid_hardness)
    |> validate_inclusion(:origin, @valid_origins)
    |> foreign_key_constraint(:attempt_id)
  end
end
