defmodule YagyeCore.Merchants.Commands.SubmitKybDocuments do
  @moduledoc false
  @enforce_keys [:merchant_id, :submitted_by]
  defstruct [:merchant_id, :submitted_by]
end
