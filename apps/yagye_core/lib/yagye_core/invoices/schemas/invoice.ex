defmodule YagyeCore.Invoices.Schemas.Invoice do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Invoices.Schemas.{InvoiceDelivery, InvoiceLineItem}

  @valid_states ~w[draft open partially_paid paid void uncollectible overdue]
  @valid_modes ~w[simulation sandbox live]

  schema "invoices" do
    field :public_id, :string
    field :merchant_id, Uniq.UUID
    field :mode, :string
    field :customer_id, Uniq.UUID
    field :number, :string
    field :state, :string, default: "draft"
    field :subtotal_amount, :integer
    field :tax_amount, :integer
    field :discount_amount, :integer
    field :total_amount, :integer
    field :amount_paid, :integer, default: 0
    field :amount_due, :integer
    field :currency, :string
    field :issue_date, :date
    field :due_date, :date
    field :payment_link_id, Uniq.UUID
    field :notes, :string
    field :terms, :string
    field :sent_at, :utc_datetime_usec
    field :paid_at, :utc_datetime_usec
    field :voided_at, :utc_datetime_usec

    has_many :line_items, InvoiceLineItem, foreign_key: :invoice_id
    has_many :deliveries, InvoiceDelivery, foreign_key: :invoice_id

    timestamps()
  end

  @required ~w[merchant_id mode customer_id number subtotal_amount tax_amount
               discount_amount total_amount amount_due currency issue_date due_date]a

  def changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [
      :merchant_id,
      :mode,
      :customer_id,
      :number,
      :state,
      :subtotal_amount,
      :tax_amount,
      :discount_amount,
      :total_amount,
      :amount_paid,
      :amount_due,
      :currency,
      :issue_date,
      :due_date,
      :payment_link_id,
      :notes,
      :terms,
      :sent_at,
      :paid_at,
      :voided_at
    ])
    |> validate_required(@required)
    |> validate_inclusion(:mode, @valid_modes)
    |> validate_inclusion(:state, @valid_states)
    |> validate_length(:currency, is: 3)
    |> validate_number(:subtotal_amount, greater_than_or_equal_to: 0)
    |> validate_number(:tax_amount, greater_than_or_equal_to: 0)
    |> validate_number(:discount_amount, greater_than_or_equal_to: 0)
    |> validate_number(:total_amount, greater_than_or_equal_to: 0)
    |> validate_number(:amount_paid, greater_than_or_equal_to: 0)
    |> validate_number(:amount_due, greater_than_or_equal_to: 0)
    |> put_public_id()
    |> unique_constraint(:public_id)
    |> unique_constraint([:merchant_id, :number])
    |> foreign_key_constraint(:merchant_id)
    |> foreign_key_constraint(:customer_id)
  end

  def state_changeset(invoice, new_state, extra \\ %{}) do
    invoice
    |> cast(Map.put(extra, :state, new_state), [:state, :sent_at, :paid_at, :voided_at])
    |> validate_inclusion(:state, @valid_states)
    |> validate_state_transition(invoice.state, new_state)
  end

  defp put_public_id(changeset) do
    if get_field(changeset, :public_id) do
      changeset
    else
      put_change(changeset, :public_id, "inv_" <> Uniq.UUID.uuid7())
    end
  end

  @allowed_transitions %{
    "draft" => ~w[open void],
    "open" => ~w[partially_paid paid void uncollectible overdue],
    "partially_paid" => ~w[paid void uncollectible overdue],
    "overdue" => ~w[paid partially_paid void uncollectible],
    "paid" => [],
    "void" => [],
    "uncollectible" => []
  }

  defp validate_state_transition(changeset, from, to) do
    allowed = Map.get(@allowed_transitions, from, [])

    if to in allowed do
      changeset
    else
      add_error(changeset, :state, "cannot transition from #{from} to #{to}")
    end
  end
end
