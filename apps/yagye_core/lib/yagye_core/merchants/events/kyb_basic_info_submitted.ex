defmodule YagyeCore.Merchants.Events.KybBasicInfoSubmitted do
  @moduledoc false
  @enforce_keys [:merchant_id, :submitted_by, :occurred_at]
  defstruct [:merchant_id, :submitted_by, :occurred_at]
end
