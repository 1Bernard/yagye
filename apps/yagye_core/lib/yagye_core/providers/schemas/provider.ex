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

    timestamps(inserted_at: :inserted_at)
  end

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [:code, :display_name, :adapter_module, :kind, :active])
    |> validate_required([:code, :display_name, :adapter_module, :kind])
    |> validate_inclusion(:kind, @valid_kinds)
    |> unique_constraint(:code)
  end
end
