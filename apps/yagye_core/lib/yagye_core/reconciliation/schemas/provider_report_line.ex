defmodule YagyeCore.Reconciliation.Schemas.ProviderReportLine do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Reconciliation.Schemas.ProviderSettlementReport

  @valid_match_states ~w[unmatched matched proposed quarantined]

  @type t :: %__MODULE__{}

  schema "provider_report_lines" do
    field :line_number, :integer
    field :provider_reference, :string
    field :transaction_type, :string
    field :gross_amount, :integer
    field :fee_amount, :integer
    field :net_amount, :integer
    field :currency, :string
    field :occurred_at, :utc_datetime_usec
    field :value_date, :date
    field :raw, :map
    field :match_state, :string, default: "unmatched"

    belongs_to :report, ProviderSettlementReport
  end

  def changeset(line, attrs) do
    line
    |> cast(attrs, [
      :report_id,
      :line_number,
      :provider_reference,
      :transaction_type,
      :gross_amount,
      :fee_amount,
      :net_amount,
      :currency,
      :occurred_at,
      :value_date,
      :raw,
      :match_state
    ])
    |> validate_required([:report_id, :line_number, :transaction_type, :raw, :match_state])
    |> validate_inclusion(:match_state, @valid_match_states)
    |> validate_number(:line_number, greater_than: 0)
    |> foreign_key_constraint(:report_id)
    |> unique_constraint([:report_id, :line_number])
  end

  def quarantine_changeset(report_id, line_number, raw) do
    %__MODULE__{}
    |> cast(
      %{
        report_id: report_id,
        line_number: line_number,
        transaction_type: "UNKNOWN",
        raw: raw || %{},
        match_state: "quarantined"
      },
      [:report_id, :line_number, :transaction_type, :raw, :match_state]
    )
    |> validate_required([:report_id, :line_number, :transaction_type, :raw, :match_state])
    |> foreign_key_constraint(:report_id)
    |> unique_constraint([:report_id, :line_number])
  end

  def match_changeset(line) do
    change(line, match_state: "matched")
  end
end
