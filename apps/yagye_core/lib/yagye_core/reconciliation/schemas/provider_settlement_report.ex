defmodule YagyeCore.Reconciliation.Schemas.ProviderSettlementReport do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Providers.Schemas.Provider

  @valid_modes ~w[simulation live]
  @valid_sources ~w[api sftp email manual_upload]

  @type t :: %__MODULE__{}

  schema "provider_settlement_reports" do
    field :mode, :string
    field :report_date, :date
    field :source, :string
    field :raw_uri, :string
    field :checksum, :string
    field :line_count, :integer
    field :reported_total, :integer
    field :currency, :string
    field :ingested_at, :utc_datetime_usec

    belongs_to :provider, Provider
  end

  def changeset(report, attrs) do
    report
    |> cast(attrs, [
      :provider_id,
      :mode,
      :report_date,
      :source,
      :raw_uri,
      :checksum,
      :line_count,
      :reported_total,
      :currency,
      :ingested_at
    ])
    |> validate_required([
      :provider_id,
      :mode,
      :report_date,
      :source,
      :raw_uri,
      :checksum,
      :line_count,
      :reported_total,
      :currency,
      :ingested_at
    ])
    |> validate_inclusion(:mode, @valid_modes)
    |> validate_inclusion(:source, @valid_sources)
    |> validate_length(:currency, is: 3)
    |> validate_number(:line_count, greater_than: 0)
    |> foreign_key_constraint(:provider_id)
    |> unique_constraint([:provider_id, :mode, :report_date, :checksum],
      name: :provider_settlement_reports_provider_id_mode_report_date_checks
    )
  end
end
