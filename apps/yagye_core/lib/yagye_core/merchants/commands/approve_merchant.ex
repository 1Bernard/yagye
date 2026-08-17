defmodule YagyeCore.Merchants.Commands.ApproveMerchant do
  @moduledoc false
  @enforce_keys [:merchant_id, :approved_by]
  defstruct [:merchant_id, :approved_by]
end
