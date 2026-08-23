defmodule YagyeCore.Repo.Migrations.AddSodFieldsToP12Tables do
  use Ecto.Migration

  def change do
    # ── merchant_reserves ────────────────────────────────────────────────────
    alter table(:merchant_reserves) do
      add :created_by, :text
      add :approved_by, :text
    end

    execute(
      "ALTER TABLE merchant_reserves ADD CONSTRAINT merchant_reserves_sod_check CHECK (approved_by IS NULL OR created_by IS NULL OR approved_by <> created_by)",
      "ALTER TABLE merchant_reserves DROP CONSTRAINT merchant_reserves_sod_check"
    )

    # ── payout_destinations ──────────────────────────────────────────────────
    alter table(:payout_destinations) do
      add :added_by, :text
      add :verified_by, :text
    end

    execute(
      "ALTER TABLE payout_destinations ADD CONSTRAINT payout_destinations_sod_check CHECK (verified_by IS NULL OR added_by IS NULL OR verified_by <> added_by)",
      "ALTER TABLE payout_destinations DROP CONSTRAINT payout_destinations_sod_check"
    )

    # ── payouts ──────────────────────────────────────────────────────────────
    alter table(:payouts) do
      add :requested_by, :text
      add :approved_by, :text
    end

    execute(
      "ALTER TABLE payouts ADD CONSTRAINT payouts_sod_check CHECK (approved_by IS NULL OR requested_by IS NULL OR approved_by <> requested_by)",
      "ALTER TABLE payouts DROP CONSTRAINT payouts_sod_check"
    )
  end
end
