defmodule YagyeCore.Routing.Schemas.RoutingRuleAction do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  schema "routing_rule_actions" do
    field :rule_id, Uniq.UUID
    field :provider_id, Uniq.UUID
    field :priority, :integer

    timestamps(updated_at: false)
  end

  def changeset(action, attrs) do
    action
    |> cast(attrs, [:rule_id, :provider_id, :priority])
    |> validate_required([:rule_id, :provider_id, :priority])
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> unique_constraint([:rule_id, :priority])
    |> foreign_key_constraint(:rule_id)
    |> foreign_key_constraint(:provider_id)
  end
end
