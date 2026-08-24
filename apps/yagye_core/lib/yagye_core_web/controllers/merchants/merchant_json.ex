defmodule YagyeCoreWeb.Controllers.Merchants.MerchantJSON do
  @moduledoc false

  alias YagyeCore.Merchants.Schemas.Merchant

  def data(%Merchant{} = m) do
    %{
      id: m.public_id,
      object: "merchant",
      legal_name: m.legal_name,
      trading_name: m.trading_name,
      country: m.country,
      default_currency: m.default_currency,
      status: m.status,
      onboarding_state: m.onboarding_state,
      kyb_tier: m.kyb_tier,
      reviewed_by: m.reviewed_by,
      approved_by: m.approved_by,
      activity_state: m.activity_state,
      api_version: m.api_version,
      inserted_at: m.inserted_at
    }
  end
end
