defmodule YagyeCore.Routing.Schemas.RoutingConfiguration do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  @valid_scopes ~w[platform merchant]
  @current_schema_version 1

  schema "routing_configurations" do
    field :public_id, :string
    field :merchant_id, Uniq.UUID
    field :scope, :string
    field :name, :string
    field :description, :string
    field :schema_version, :integer, default: @current_schema_version
    field :graph_payload, :map
    field :compiled_rules, :map
    field :state, :string, default: "draft"
    field :published_at, :utc_datetime_usec
    field :archived_at, :utc_datetime_usec
    timestamps()
  end

  def create_changeset(config, attrs) do
    config
    |> cast(attrs, [:merchant_id, :scope, :name, :description, :graph_payload])
    |> validate_required([:scope, :name, :graph_payload])
    |> validate_inclusion(:scope, @valid_scopes)
    |> put_change(:public_id, generate_public_id())
    |> put_change(:state, "draft")
    |> put_change(:schema_version, @current_schema_version)
  end

  def update_changeset(config, attrs) do
    config
    |> validate_state("draft")
    |> cast(attrs, [:name, :description, :graph_payload])
    |> validate_required([:name, :graph_payload])
  end

  def publish_changeset(config) do
    config
    |> validate_state("draft")
    |> put_change(:state, "published")
    |> put_change(:published_at, DateTime.utc_now())
  end

  def archive_changeset(config) do
    config
    |> validate_state("published")
    |> put_change(:state, "archived")
    |> put_change(:archived_at, DateTime.utc_now())
  end

  defp validate_state(%{data: %{state: actual}} = cs, expected) do
    if actual == expected do
      cs
    else
      add_error(cs, :state, "must be #{expected} for this operation")
    end
  end

  defp validate_state(config, expected) when is_struct(config) do
    Ecto.Changeset.change(config)
    |> validate_state(expected)
  end

  defp generate_public_id do
    "rcfg_" <> Base.encode32(:crypto.strong_rand_bytes(10), padding: false, case: :lower)
  end
end
