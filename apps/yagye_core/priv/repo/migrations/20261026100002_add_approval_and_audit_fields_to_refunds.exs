defmodule YagyeCore.Repo.Migrations.AddApprovalAndAuditFieldsToRefunds do
  use Ecto.Migration

  def change do
    alter table(:refunds) do
      # Who initiated the refund: "portal_user:usr_X", "merchant_api", "ops_user:usr_X"
      add :initiated_by, :string

      # Approval fields — populated only for refunds that required ops sign-off.
      add :approved_by, :string
      add :approved_at, :utc_datetime_usec
      add :approval_reason, :string

      # Provider-level reference returned after successful disbursement dispatch.
      add :provider_ref, :string

      # Full raw response body from the provider (or simulator) on dispatch.
      add :provider_response, :map

      # Append-only state-transition audit log:
      # [{from, to, at, by, reason}] — each refund state change appends an entry.
      add :state_transitions, {:array, :map}, default: []
    end

    # SoD: the person who approves cannot be the one who initiated.
    # Only enforced when both are set (ops-approval flow).
    create constraint(:refunds, :sod_approver_differs_from_initiator,
             check: "approved_by IS NULL OR initiated_by IS NULL OR approved_by != initiated_by"
           )
  end
end
