defmodule YagyeCore.Merchants.Commands.RevokeApiKey do
  @moduledoc false
  @enforce_keys [:api_key_id, :merchant_id, :revoked_by]
  defstruct [:api_key_id, :merchant_id, :revoked_by]
end
