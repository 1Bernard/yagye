defmodule YagyeCoreWeb.Controllers.Customers.CustomerJSON do
  @moduledoc false

  alias YagyeCore.Customers.Schemas.Customer
  alias YagyeCore.Payments.Schemas.AccountVerification

  def list(%{data: customers, has_more: has_more}) do
    %{object: "list", data: Enum.map(customers, &data/1), has_more: has_more}
  end

  def data(%Customer{} = c) do
    %{
      id: c.public_id,
      object: "customer",
      merchant_customer_ref: c.merchant_customer_ref,
      kyc_tier: c.kyc_tier,
      kyc_verified_at: c.kyc_verified_at,
      inserted_at: c.inserted_at
    }
  end

  def verification_list(%{data: verifications, has_more: has_more}) do
    %{object: "list", data: Enum.map(verifications, &verification_data/1), has_more: has_more}
  end

  def verification_data(%AccountVerification{} = av) do
    %{
      id: av.id,
      object: "account_verification",
      verification_type: av.verification_type,
      provider_code: av.provider_code,
      account_masked: av.account_masked,
      network: av.network,
      bank_code: av.bank_code,
      account_name_returned: av.account_name_returned,
      kyc_tier_returned: av.kyc_tier_returned,
      name_match_score: av.name_match_score,
      state: av.state,
      inserted_at: av.inserted_at
    }
  end
end
