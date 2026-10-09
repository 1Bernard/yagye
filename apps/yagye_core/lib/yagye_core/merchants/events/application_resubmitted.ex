defmodule YagyeCore.Merchants.Events.ApplicationResubmitted do
  @moduledoc false
  @enforce_keys [:application_id, :merchant_id, :resubmitted_by, :occurred_at]
  defstruct [:application_id, :merchant_id, :resubmitted_by, :occurred_at]
end
