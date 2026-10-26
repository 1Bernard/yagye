defmodule YagyeCore.Repo.Migrations.UpdateValidStateConstraintsForRefunds do
  use Ecto.Migration

  def change do
    # Add partially_refunded to the payments state constraint.
    drop constraint(:payments, :valid_state)

    create constraint(:payments, :valid_state,
             check:
               "state IN ('created','processing','requires_action','authorised','succeeded'," <>
                 "'failed','cancelled','indeterminate','disputed','refunded','partially_refunded','chargebacked')"
           )

    # Add pending_approval, approved, rejected to the refunds state constraint.
    drop constraint(:refunds, :valid_state)

    create constraint(:refunds, :valid_state,
             check:
               "state IN ('pending_approval','approved','requested','succeeded','failed','rejected')"
           )
  end
end
