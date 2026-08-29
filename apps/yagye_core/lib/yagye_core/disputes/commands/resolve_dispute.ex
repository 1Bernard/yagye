defmodule YagyeCore.Disputes.Commands.ResolveDispute do
  @moduledoc false
  @enforce_keys [:dispute_id, :outcome]
  defstruct [:dispute_id, :outcome]
end
