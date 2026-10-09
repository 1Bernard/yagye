defmodule YagyeCore.Merchants.Commands.ResubmitMerchantApplication do
  @moduledoc false
  @enforce_keys [:merchant_id, :resubmitted_by]
  defstruct [:merchant_id, :resubmitted_by]
end
