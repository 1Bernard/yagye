defmodule YagyeCore.Merchants.Commands.RejectMerchantApplication do
  @moduledoc false
  @enforce_keys [:application_id, :rejected_by, :reason]
  defstruct [:application_id, :rejected_by, :reason]
end
