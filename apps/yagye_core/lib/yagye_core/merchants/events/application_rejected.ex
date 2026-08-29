defmodule YagyeCore.Merchants.Events.ApplicationRejected do
  @moduledoc false
  @enforce_keys [:application_id, :rejected_by, :reason, :occurred_at]
  defstruct [:application_id, :rejected_by, :reason, :occurred_at]
end
