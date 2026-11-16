defmodule YagyeCore.Repo.Migrations.AddWeightedSplitToRouting do
  use Ecto.Migration

  def change do
    alter table(:routing_rules) do
      # Groups sibling rules produced by the same SplitNode compilation.
      # NULL for all non-split rules; a UUID shared by both branches of a split.
      add :split_group_id, :uuid, null: true

      # Traffic weight for weighted random selection within a split group.
      # Integer units (not %) — ratio between siblings determines split fraction.
      # Default 100 so non-split rules behave identically to before.
      add :weight, :integer, null: false, default: 100
    end

    create constraint(:routing_rules, :positive_weight, check: "weight > 0")

    create index(:routing_rules, [:split_group_id],
             where: "split_group_id IS NOT NULL",
             name: :routing_rules_split_group_id_index
           )
  end
end
