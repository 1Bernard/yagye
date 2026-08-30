defmodule YagyeCore.Routing.Commands.CreateRoutingRule do
  @moduledoc false
  @enforce_keys [:scope, :mode, :name, :priority]
  defstruct [
    :scope,
    :merchant_id,
    :mode,
    :name,
    :priority,
    active: true,
    conditions: [],
    actions: []
  ]
end
