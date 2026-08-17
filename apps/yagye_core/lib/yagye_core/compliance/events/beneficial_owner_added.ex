defmodule YagyeCore.Compliance.Events.BeneficialOwnerAdded do
  @moduledoc false
  @enforce_keys [:beneficial_owner_id, :merchant_id, :subject_ref, :role, :occurred_at]
  defstruct [:beneficial_owner_id, :merchant_id, :subject_ref, :role, :ownership_bps, :occurred_at]
end
