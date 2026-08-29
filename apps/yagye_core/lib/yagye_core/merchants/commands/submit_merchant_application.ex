defmodule YagyeCore.Merchants.Commands.SubmitMerchantApplication do
  @moduledoc false
  @enforce_keys [
    :first_name,
    :last_name,
    :email,
    :legal_name,
    :trading_name,
    :country,
    :default_currency
  ]
  defstruct [
    :first_name,
    :last_name,
    :email,
    :phone_number,
    :job_title,
    :legal_name,
    :trading_name,
    :country,
    :default_currency,
    :industry,
    :employee_range,
    :annual_tpv_estimate_cents,
    :website_url,
    :use_case,
    expected_methods: []
  ]
end
