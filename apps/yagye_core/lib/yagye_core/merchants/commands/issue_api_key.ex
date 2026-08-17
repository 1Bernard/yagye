defmodule YagyeCore.Merchants.Commands.IssueApiKey do
  @moduledoc false
  @enforce_keys [:merchant_id, :mode, :kind, :scopes]
  defstruct [:merchant_id, :mode, :kind, :scopes, :expires_at, :created_by]
end
