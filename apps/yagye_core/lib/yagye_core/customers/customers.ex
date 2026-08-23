defmodule YagyeCore.Customers do
  @moduledoc false

  alias YagyeCore.Customers.Schemas.Customer
  alias YagyeCore.Repo

  # ── Public API ───────────────────────────────────────────────────────────────

  @doc """
  Finds or creates a customer record for a merchant.

  Keyed on (merchant_id, merchant_customer_ref). Safe to call on every payment —
  returns the existing record if already present.
  """
  def find_or_create(merchant_id, merchant_customer_ref, attrs \\ %{}) do
    attrs =
      Map.merge(attrs, %{merchant_id: merchant_id, merchant_customer_ref: merchant_customer_ref})

    case Repo.insert(Customer.create_changeset(%Customer{}, attrs),
           on_conflict: :nothing,
           conflict_target: [:merchant_id, :merchant_customer_ref]
         ) do
      {:ok, _} ->
        {:ok,
         Repo.get_by!(Customer,
           merchant_id: merchant_id,
           merchant_customer_ref: merchant_customer_ref
         )}

      {:error, _} = err ->
        err
    end
  end

  def get_customer(customer_id) do
    case Repo.get(Customer, customer_id) do
      nil -> {:error, :not_found}
      customer -> {:ok, customer}
    end
  end

  @doc """
  Updates the KYC tier on a customer record, typically after a successful name enquiry.
  """
  def update_kyc_tier(customer, kyc_tier, verified_at \\ nil) do
    customer
    |> Customer.update_kyc_tier_changeset(kyc_tier, verified_at)
    |> Repo.update()
  end
end
