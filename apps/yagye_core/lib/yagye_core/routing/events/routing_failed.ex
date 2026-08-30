defmodule YagyeCore.Routing.Events.RoutingFailed do
  @moduledoc false
  defstruct [:merchant_id, :mode, :reason, :occurred_at]
end
