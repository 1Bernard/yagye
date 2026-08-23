defmodule YagyeCore.BankReconciliation.Schemas.BankStatementLine do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.BankReconciliation.Schemas.BankStatement

  @valid_match_states ~w[unmatched matched disputed written_off]

  @type t :: %__MODULE__{}

  schema "bank_statement_lines" do
    field :line_number, :integer
    field :value_date, :date
    field :amount, :integer
    field :currency, :string
    field :narrative, :string
    field :bank_reference, :string
    field :counterparty, :string
    field :match_state, :string, default: "unmatched"

    belongs_to :statement, BankStatement

    field :inserted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def create_changeset(line, attrs) do
    line
    |> cast(attrs, [
      :statement_id,
      :line_number,
      :value_date,
      :amount,
      :currency,
      :narrative,
      :bank_reference,
      :counterparty
    ])
    |> validate_required([
      :statement_id,
      :line_number,
      :value_date,
      :amount,
      :currency,
      :narrative
    ])
    |> validate_length(:currency, is: 3)
    |> foreign_key_constraint(:statement_id)
    |> unique_constraint([:statement_id, :line_number])
  end

  def match_changeset(line, state) when state in @valid_match_states do
    change(line, match_state: state)
  end
end
