defmodule YagyeCore.Compliance.Commands.SubmitOnboardingDetails do
  @moduledoc false
  @enforce_keys [:merchant_id, :business_type, :website_url]
  defstruct [
    :merchant_id,
    :business_type,
    :website_url,
    :expected_monthly_volume_minor,
    :expected_monthly_volume_currency
  ]
end
