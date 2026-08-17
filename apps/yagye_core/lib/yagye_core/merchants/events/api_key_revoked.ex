defmodule YagyeCore.Merchants.Events.ApiKeyRevoked do
  @moduledoc false
  @enforce_keys [:api_key_id, :merchant_id, :revoked_by, :occurred_at]
  defstruct [:api_key_id, :merchant_id, :revoked_by, :occurred_at]
end
