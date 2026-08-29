defmodule YagyeCore.Merchants.Events.ApplicationReviewStarted do
  @moduledoc false
  @enforce_keys [:application_id, :reviewed_by, :occurred_at]
  defstruct [:application_id, :reviewed_by, :occurred_at]
end
