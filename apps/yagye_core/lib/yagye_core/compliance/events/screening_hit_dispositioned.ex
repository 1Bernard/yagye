defmodule YagyeCore.Compliance.Events.ScreeningHitDispositioned do
  @moduledoc false
  @enforce_keys [
    :screening_hit_id,
    :merchant_id,
    :status,
    :disposition_reason,
    :dispositioned_by,
    :occurred_at
  ]
  defstruct [
    :screening_hit_id,
    :merchant_id,
    :status,
    :disposition_reason,
    :dispositioned_by,
    :occurred_at
  ]
end
