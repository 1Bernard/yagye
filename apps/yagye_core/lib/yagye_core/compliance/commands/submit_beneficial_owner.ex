defmodule YagyeCore.Compliance.Commands.SubmitBeneficialOwner do
  @moduledoc false
  @enforce_keys [:merchant_id, :subject_ref, :role]
  defstruct [:merchant_id, :subject_ref, :role, :ownership_bps]
end
