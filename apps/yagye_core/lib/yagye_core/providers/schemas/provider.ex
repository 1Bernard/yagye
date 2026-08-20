defmodule YagyeCore.Providers.Schemas.Provider do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  schema "providers" do
    field :code, :string
    field :display_name, :string
    field :adapter_module, :string
    field :active, :boolean, default: true

    timestamps(inserted_at: :inserted_at)
  end

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [:code, :display_name, :adapter_module, :active])
    |> validate_required([:code, :display_name, :adapter_module])
    |> unique_constraint(:code)
  end
end
