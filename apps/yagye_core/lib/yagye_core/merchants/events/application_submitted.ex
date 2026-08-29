defmodule YagyeCore.Merchants.Events.ApplicationSubmitted do
  @moduledoc false
  @enforce_keys [
    :application_id,
    :public_id,
    :email,
    :legal_name,
    :trading_name,
    :country,
    :occurred_at
  ]
  defstruct [
    :application_id,
    :public_id,
    :email,
    :legal_name,
    :trading_name,
    :country,
    :occurred_at
  ]
end
