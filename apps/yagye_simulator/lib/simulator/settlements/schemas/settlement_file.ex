defmodule Simulator.Settlements.Schemas.SettlementFile do
  @moduledoc false

  use Simulator.Schema
  import Ecto.Changeset

  alias Simulator.Accounts.Schemas.Account
  alias Simulator.Settlements.Schemas.SettlementLine

  schema "gw_settlement_files" do
    field :file_ref, :string
    field :settlement_date, :date
    field :format, :string, default: "JSON"
    field :currency, :string
    field :gross_minor, :integer
    field :fee_minor, :integer
    field :net_minor, :integer
    field :line_count, :integer
    field :injected_defect, :string
    field :generated_at, :utc_datetime_usec

    belongs_to :account, Account
    has_many :lines, SettlementLine, foreign_key: :file_id
  end

  def changeset(file, attrs) do
    file
    |> cast(attrs, [
      :account_id,
      :file_ref,
      :settlement_date,
      :format,
      :currency,
      :gross_minor,
      :fee_minor,
      :net_minor,
      :line_count,
      :injected_defect,
      :generated_at
    ])
    |> validate_required([
      :account_id,
      :file_ref,
      :settlement_date,
      :currency,
      :line_count,
      :generated_at
    ])
    |> unique_constraint(:file_ref)
  end
end
