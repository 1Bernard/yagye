defmodule YagyeCore.Merchants.Events.MerchantRegistered do
  @moduledoc false
  @enforce_keys [
    :merchant_id,
    :public_id,
    :legal_name,
    :trading_name,
    :country,
    :default_currency,
    :occurred_at
  ]
  defstruct [
    :merchant_id,
    :public_id,
    :legal_name,
    :trading_name,
    :country,
    :default_currency,
    :occurred_at
  ]
end
