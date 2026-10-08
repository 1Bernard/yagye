defmodule YagyeCore.Repo.Migrations.P21SodDbChecks do
  use Ecto.Migration

  def change do
    # screening_hits: the person who raises a hit cannot be the person who dispositions it.
    # NULL dispositioned_by means not yet dispositioned — always allowed.
    execute(
      """
      ALTER TABLE screening_hits
        ADD CONSTRAINT screening_hits_sod
        CHECK (dispositioned_by IS NULL OR raised_by IS DISTINCT FROM dispositioned_by)
      """,
      "ALTER TABLE screening_hits DROP CONSTRAINT IF EXISTS screening_hits_sod"
    )

    # merchants: the person who reviews a KYB cannot be the person who approves it.
    # NULL approved_by means not yet approved — always allowed.
    execute(
      """
      ALTER TABLE merchants
        ADD CONSTRAINT merchants_sod
        CHECK (approved_by IS NULL OR reviewed_by IS DISTINCT FROM approved_by)
      """,
      "ALTER TABLE merchants DROP CONSTRAINT IF EXISTS merchants_sod"
    )
  end
end
