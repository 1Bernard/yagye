defmodule YagyeCore.Payments.AccountVerification do
  @moduledoc false

  alias YagyeCore.Customers
  alias YagyeCore.Payments.ProviderAdapter
  alias YagyeCore.Payments.Schemas.AccountVerification
  alias YagyeCore.Repo

  # ── Public API ───────────────────────────────────────────────────────────────

  @doc """
  Performs a mobile money name enquiry and stores the result.

  Calls the provider's name_enquiry/2 adapter callback, persists the verification
  record, and — if a customer_id is provided — updates the customer's KYC tier
  from the result.

  Returns `{:ok, %{account_name: name, kyc_tier: tier, verification_id: id}}`
  or `{:error, reason}`.
  """
  def enquire_name(merchant_id, msisdn, network, provider_code, credential, opts \\ []) do
    customer_id = Keyword.get(opts, :customer_id)
    payment_id = Keyword.get(opts, :payment_id)

    account_hash = hmac_msisdn(msisdn)
    account_masked = mask_msisdn(msisdn)

    verification =
      AccountVerification.create_changeset(%AccountVerification{}, %{
        merchant_id: merchant_id,
        payment_id: payment_id,
        verification_type: "mobile_money",
        provider_code: provider_code,
        account_hash: account_hash,
        account_masked: account_masked,
        network: network
      })

    with {:ok, pending} <- Repo.insert(verification),
         {:ok, result} <-
           ProviderAdapter.adapter().name_enquiry(
             %{msisdn: msisdn, network: String.upcase(network)},
             credential
           ) do
      complete_attrs = %{
        account_name_returned: result.account_name,
        kyc_tier_returned: result.kyc_tier,
        state: "verified",
        raw_response: Map.new(result)
      }

      {:ok, completed} =
        pending
        |> AccountVerification.complete_changeset(complete_attrs)
        |> Repo.update()

      maybe_update_customer_kyc(customer_id, result.kyc_tier)

      {:ok,
       %{
         account_name: completed.account_name_returned,
         kyc_tier: completed.kyc_tier_returned,
         verification_id: completed.id
       }}
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp maybe_update_customer_kyc(nil, _tier), do: :ok
  defp maybe_update_customer_kyc(_id, nil), do: :ok

  defp maybe_update_customer_kyc(customer_id, kyc_tier) do
    case Customers.get_customer(customer_id) do
      {:ok, customer} -> Customers.update_kyc_tier(customer, kyc_tier)
      _ -> :ok
    end
  end

  defp hmac_msisdn(msisdn) do
    key =
      Application.get_env(:yagye_core, :account_verification_hmac_key, "yagye_acct_verify_dev")

    :crypto.mac(:hmac, :sha256, key, msisdn) |> Base.encode16(case: :lower)
  end

  defp mask_msisdn(msisdn) do
    digits = String.replace(msisdn, ~r/\D/, "")
    len = String.length(digits)

    if len >= 7 do
      visible_prefix = String.slice(digits, 0, 3)
      visible_suffix = String.slice(digits, -4, 4)
      masked_count = len - 7
      masked = String.duplicate("X", max(masked_count, 0))
      "#{visible_prefix}#{masked}#{visible_suffix}"
    else
      msisdn
    end
  end
end
