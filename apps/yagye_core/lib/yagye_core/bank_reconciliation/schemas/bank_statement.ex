defmodule YagyeCore.BankReconciliation.Schemas.BankStatement do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  @valid_sources ~w[api open_banking csv_upload mt940]

  @type t :: %__MODULE__{}

  schema "bank_statements" do
    field :account_reference, :string
    field :mode, :string
    field :statement_date, :date
    field :source, :string
    field :raw_uri, :string
    field :checksum, :string
    field :opening_balance, :integer
    field :closing_balance, :integer
    field :currency, :string

    has_many :lines, YagyeCore.BankReconciliation.Schemas.BankStatementLine,
      foreign_key: :statement_id

    field :ingested_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def create_changeset(statement, attrs) do
    statement
    |> cast(attrs, [
      :account_reference,
      :mode,
      :statement_date,
      :source,
      :raw_uri,
      :checksum,
      :opening_balance,
      :closing_balance,
      :currency
    ])
    |> validate_required([
      :account_reference,
      :mode,
      :statement_date,
      :source,
      :raw_uri,
      :checksum,
      :opening_balance,
      :closing_balance,
      :currency
    ])
    |> validate_inclusion(:source, @valid_sources)
    |> validate_inclusion(:mode, ~w[simulation live])
    |> validate_length(:currency, is: 3)
    |> unique_constraint([:account_reference, :statement_date, :checksum])
  end
end
