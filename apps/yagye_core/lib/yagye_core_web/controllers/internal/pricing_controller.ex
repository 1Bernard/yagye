defmodule YagyeCoreWeb.Controllers.Internal.PricingController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Merchants
  alias YagyeCore.Pricing
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  # GET /internal/merchants/:merchant_code/pricing-plan
  def show_plan(conn, %{"merchant_code" => merchant_code}) do
    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, plan} <- Pricing.get_merchant_plan(merchant.id) do
      Response.ok(conn, plan_data(plan))
    end
  end

  # GET /internal/merchants/:merchant_code/fee-invoices
  def list_fee_invoices(conn, %{"merchant_code" => merchant_code} = params) do
    limit = params["limit"] && String.to_integer(params["limit"])
    offset = params["offset"] && String.to_integer(params["offset"])

    opts =
      [limit: limit, offset: offset]
      |> Keyword.reject(fn {_, v} -> is_nil(v) end)

    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, invoices} <- Pricing.list_fee_invoices(merchant.id, opts) do
      Response.ok(conn, %{
        object: "list",
        data: Enum.map(invoices, &invoice_data/1)
      })
    end
  end

  # ── Private serialisers ──────────────────────────────────────────────────────

  defp plan_data(plan) do
    %{
      object: "pricing_plan",
      id: plan.public_id,
      name: plan.name,
      version: plan.version,
      currency: plan.currency,
      fee_mode: plan.fee_mode,
      monthly_fee: plan.monthly_fee,
      effective_from: plan.effective_from,
      effective_to: plan.effective_to,
      rules: Enum.map(plan.rules, &rule_data/1)
    }
  end

  defp rule_data(rule) do
    %{
      id: rule.id,
      method: rule.method,
      provider_code: rule.provider_code,
      card_brand: rule.card_brand,
      region: rule.region,
      amount_min: rule.amount_min,
      amount_max: rule.amount_max,
      percentage_bps: rule.percentage_bps,
      fixed_amount: rule.fixed_amount,
      minimum_fee: rule.minimum_fee,
      maximum_fee: rule.maximum_fee,
      rounding: rule.rounding
    }
  end

  defp invoice_data(inv) do
    %{
      id: inv.public_id,
      period_start: inv.period_start,
      period_end: inv.period_end,
      currency: inv.currency,
      total_amount: inv.total_amount,
      collection_method: inv.collection_method,
      state: inv.state,
      due_at: inv.due_at,
      collected_at: inv.collected_at,
      inserted_at: inv.inserted_at
    }
  end
end
