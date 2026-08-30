defmodule YagyeCore.Routing.Events.RoutingResolved do
  @moduledoc false
  defstruct [:merchant_id, :mode, :rule_id, :provider_id, :occurred_at]
end
