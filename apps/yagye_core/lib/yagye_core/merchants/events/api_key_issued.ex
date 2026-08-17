defmodule YagyeCore.Merchants.Events.ApiKeyIssued do
  @moduledoc false
  @enforce_keys [:api_key_id, :public_id, :merchant_id, :mode, :kind, :key_prefix, :scopes, :occurred_at]
  defstruct [:api_key_id, :public_id, :merchant_id, :mode, :kind, :key_prefix, :scopes, :expires_at, :occurred_at]
end
