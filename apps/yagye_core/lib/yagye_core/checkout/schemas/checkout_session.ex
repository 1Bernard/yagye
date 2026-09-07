defmodule YagyeCore.Checkout.Schemas.CheckoutSession do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Checkout.Schemas.{CheckoutEvent, CheckoutLineItem}

  @valid_states ~w[open processing completed cancelled expired]
  @valid_modes ~w[simulation sandbox live]

  schema "checkout_sessions" do
    field :public_id, :string
    field :merchant_id, Uniq.UUID
    field :mode, :string
    field :url_token_hash, :string
    field :state, :string, default: "open"
    field :subtotal_amount, :integer
    field :tax_amount, :integer, default: 0
    field :shipping_amount, :integer, default: 0
    field :discount_amount, :integer, default: 0
    field :total_amount, :integer
    field :currency, :string
    field :merchant_reference, :string
    field :description, :string
    field :collect_email, :boolean, default: false
    field :collect_phone, :boolean, default: false
    field :collect_name, :boolean, default: false
    field :customer_subject_ref, Uniq.UUID
    field :allowed_methods, {:array, :string}, default: []
    field :locale, :string, default: "en"
    field :success_url, :string
    field :cancel_url, :string
    field :template_id, Uniq.UUID
    field :payment_link_id, Uniq.UUID
    field :payment_id, Uniq.UUID
    field :metadata, :map, default: %{}
    field :expires_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    has_many :line_items, CheckoutLineItem, foreign_key: :session_id
    has_many :events, CheckoutEvent, foreign_key: :session_id

    timestamps(inserted_at: :inserted_at)
  end

  @required ~w[merchant_id mode url_token_hash subtotal_amount tax_amount shipping_amount
               discount_amount total_amount currency merchant_reference success_url cancel_url
               expires_at]a

  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :merchant_id,
      :mode,
      :url_token_hash,
      :state,
      :subtotal_amount,
      :tax_amount,
      :shipping_amount,
      :discount_amount,
      :total_amount,
      :currency,
      :merchant_reference,
      :description,
      :collect_email,
      :collect_phone,
      :collect_name,
      :customer_subject_ref,
      :allowed_methods,
      :locale,
      :success_url,
      :cancel_url,
      :template_id,
      :payment_link_id,
      :payment_id,
      :metadata,
      :expires_at,
      :completed_at
    ])
    |> validate_required(@required)
    |> validate_inclusion(:mode, @valid_modes)
    |> validate_inclusion(:state, @valid_states)
    |> validate_length(:currency, is: 3)
    |> validate_number(:total_amount, greater_than: 0)
    |> validate_amount_sum()
    |> put_public_id()
    |> unique_constraint(:public_id)
    |> unique_constraint(:url_token_hash)
    |> foreign_key_constraint(:merchant_id)
    |> foreign_key_constraint(:payment_link_id)
    |> foreign_key_constraint(:template_id)
    |> foreign_key_constraint(:payment_id)
  end

  def state_changeset(session, new_state, extra \\ %{}) do
    session
    |> cast(Map.put(extra, :state, new_state), [:state, :completed_at, :payment_id])
    |> validate_inclusion(:state, @valid_states)
    |> validate_state_transition(session.state, new_state)
  end

  defp validate_amount_sum(changeset) do
    subtotal = get_field(changeset, :subtotal_amount) || 0
    tax = get_field(changeset, :tax_amount) || 0
    shipping = get_field(changeset, :shipping_amount) || 0
    discount = get_field(changeset, :discount_amount) || 0
    total = get_field(changeset, :total_amount)

    if total && subtotal + tax + shipping - discount != total do
      add_error(changeset, :total_amount, "must equal subtotal + tax + shipping - discount")
    else
      changeset
    end
  end

  @allowed_transitions %{
    "open" => ~w[processing cancelled expired],
    "processing" => ~w[completed cancelled expired],
    "completed" => [],
    "cancelled" => [],
    "expired" => []
  }

  defp validate_state_transition(changeset, from, to) do
    if to in Map.get(@allowed_transitions, from, []) do
      changeset
    else
      add_error(changeset, :state, "cannot transition from #{from} to #{to}")
    end
  end

  defp put_public_id(changeset) do
    if get_field(changeset, :public_id) do
      changeset
    else
      put_change(changeset, :public_id, "cks_" <> Uniq.UUID.uuid7())
    end
  end
end
