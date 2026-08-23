defmodule YagyeCore.Providers.Schemas.Provider do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  @valid_kinds ~w[native_rail external_psp]

  schema "providers" do
    field :code, :string
    field :display_name, :string
    field :adapter_module, :string
    field :kind, :string, default: "native_rail"
    field :active, :boolean, default: true
    field :settlement_cadence, :map, default: %{}

    timestamps(inserted_at: :inserted_at)
  end

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [:code, :display_name, :adapter_module, :kind, :active, :settlement_cadence])
    |> validate_required([:code, :display_name, :adapter_module, :kind])
    |> validate_inclusion(:kind, @valid_kinds)
    |> validate_settlement_cadence()
    |> unique_constraint(:code)
  end

  # {} means "use platform default (23:00 Africa/Accra)".
  # A non-empty map must have exactly cutoff_hour (0–23) and timezone (non-empty string).
  defp validate_settlement_cadence(changeset) do
    case get_change(changeset, :settlement_cadence) do
      nil ->
        changeset

      cadence when map_size(cadence) == 0 ->
        changeset

      %{"cutoff_hour" => h, "timezone" => tz}
      when is_integer(h) and h >= 0 and h <= 23 and is_binary(tz) and byte_size(tz) > 0 ->
        changeset

      _ ->
        add_error(
          changeset,
          :settlement_cadence,
          "must be {} (platform default) or %{\"cutoff_hour\" => 0–23, \"timezone\" => \"Region/City\"}"
        )
    end
  end
end
