defmodule YagyeCore.Merchants.Commands.ApproveMerchantApplication do
  @moduledoc false
  @enforce_keys [:application_id, :approved_by]
  defstruct [:application_id, :approved_by]
end
