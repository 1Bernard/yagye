defmodule YagyeCore.Merchants.Commands.RegisterMerchant do
  @moduledoc false
  @enforce_keys [:legal_name, :trading_name, :country, :default_currency]
  defstruct [:legal_name, :trading_name, :country, :default_currency, :metadata]
end
