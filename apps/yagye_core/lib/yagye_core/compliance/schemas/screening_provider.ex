defmodule YagyeCore.Compliance.Schemas.ScreeningProvider do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:code, :string, autogenerate: false}
  schema "screening_providers" do
    field :display_name, :string
    field :adapter_module, :string
    field :supported_lists, {:array, :string}
    field :default_lists, {:array, :string}
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [
      :code,
      :display_name,
      :adapter_module,
      :supported_lists,
      :default_lists,
      :active
    ])
    |> validate_required([
      :code,
      :display_name,
      :adapter_module,
      :supported_lists,
      :default_lists
    ])
  end
end
