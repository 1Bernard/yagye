defmodule YagyeCore.Merchants.Events.ApplicationApproved do
  @moduledoc false
  @enforce_keys [:application_id, :approved_by, :merchant_id, :merchant_public_id, :occurred_at]
  defstruct [:application_id, :approved_by, :merchant_id, :merchant_public_id, :occurred_at]
end
