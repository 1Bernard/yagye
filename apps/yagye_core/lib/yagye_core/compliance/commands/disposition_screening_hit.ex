defmodule YagyeCore.Compliance.Commands.DispositionScreeningHit do
  @moduledoc false
  @enforce_keys [:screening_hit_id, :merchant_id, :status, :disposition_reason, :dispositioned_by]
  defstruct [:screening_hit_id, :merchant_id, :status, :disposition_reason, :dispositioned_by]
end
