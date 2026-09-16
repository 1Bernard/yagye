defmodule Simulator.Settlements.Schemas.SettlementLine do
  @moduledoc false

  use Simulator.Schema
  import Ecto.Changeset

  alias Simulator.Settlements.Schemas.SettlementFile

  schema "gw_settlement_lines" do
    field :line_number, :integer
    field :charge_ref, :string
    field :line_type, :string
    field :gross_minor, :integer
    field :fee_minor, :integer
    field :net_minor, :integer
    field :value_date, :date
    field :malformed, :boolean, default: false

    belongs_to :file, SettlementFile
  end

  def changeset(line, attrs) do
    line
    |> cast(attrs, [
      :file_id,
      :line_number,
      :charge_ref,
      :line_type,
      :gross_minor,
      :fee_minor,
      :net_minor,
      :value_date,
      :malformed
    ])
    |> validate_required([:file_id, :line_number, :line_type])
    |> unique_constraint([:file_id, :line_number])
    |> foreign_key_constraint(:file_id)
  end
end
