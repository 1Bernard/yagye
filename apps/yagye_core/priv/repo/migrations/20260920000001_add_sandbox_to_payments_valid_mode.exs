defmodule YagyeCore.Repo.Migrations.AddSandboxToPaymentsValidMode do
  use Ecto.Migration

  def up do
    drop constraint(:payments, :valid_mode)
    create constraint(:payments, :valid_mode, check: "mode IN ('simulation','sandbox','live')")
  end

  def down do
    drop constraint(:payments, :valid_mode)
    create constraint(:payments, :valid_mode, check: "mode IN ('simulation','live')")
  end
end
