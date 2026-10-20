defmodule YagyeCore.Repo.Migrations.RenameAnnualTpvEstimateCentsToMinor do
  use Ecto.Migration

  # Renames annual_tpv_estimate_cents → annual_tpv_estimate to align with the
  # system-wide convention (all monetary schema fields use bare _amount / no suffix,
  # not _cents which implies USD, and not _minor which is used only in local variables).
  def change do
    rename table(:merchant_applications), :annual_tpv_estimate_cents, to: :annual_tpv_estimate
    rename table(:merchants), :annual_tpv_estimate_cents, to: :annual_tpv_estimate
  end
end
