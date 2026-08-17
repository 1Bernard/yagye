defmodule YagyeCore.Merchants.Events.MerchantApproved do
  @moduledoc false
  @enforce_keys [:merchant_id, :approved_by, :occurred_at]
  defstruct [:merchant_id, :approved_by, :occurred_at]
end
