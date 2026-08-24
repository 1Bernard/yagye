defmodule YagyeCore.Merchants.Commands.StartKybReview do
  @moduledoc false
  @enforce_keys [:merchant_id, :reviewed_by]
  defstruct [:merchant_id, :reviewed_by]
end
