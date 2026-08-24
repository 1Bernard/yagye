defmodule YagyeCore.Merchants.Events.KybReviewStarted do
  @moduledoc false
  @enforce_keys [:merchant_id, :reviewed_by, :occurred_at]
  defstruct [:merchant_id, :reviewed_by, :occurred_at]
end
