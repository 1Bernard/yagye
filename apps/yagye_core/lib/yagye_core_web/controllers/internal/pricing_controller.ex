defmodule YagyeCoreWeb.Controllers.Internal.PricingController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Merchants
  alias YagyeCore.Pricing
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  # GET /internal/pricing-plans
  def list_plans(conn, _params) do
    {:ok, plans} = Pricing.list_plans()
    Response.ok(conn, %{object: "list", data: Enum.map(plans, &plan_summary/1)})
  end

  # POST /internal/pricing-plans
  def create_plan(conn, params) do
    attrs = %{
      name: params["name"],
      version: params["version"] && String.to_integer(to_string(params["version"])),
      currency: params["currency"],
      fee_mode: params["fee_mode"],
      monthly_fee: params["monthly_fee"] && String.to_integer(to_string(params["monthly_fee"])),
      effective_from: params["effective_from"]
    }

    case Pricing.create_plan(attrs) do
      {:ok, plan} ->
        conn |> put_status(:created) |> json(plan_summary(plan))

      {:error, %Ecto.Changeset{} = cs} ->
        errors = Ecto.Changeset.traverse_errors(cs, fn {msg, _} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_failed", details: errors})
    end
  end

  # GET /internal/pricing-plans/:plan_id
  def get_plan(conn, %{"plan_id" => plan_id}) do
    case Pricing.get_plan(plan_id) do
      {:ok, plan} -> Response.ok(conn, plan_data(plan))
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "plan_not_found"})
    end
  end

  # POST /internal/pricing-plans/:plan_id/rules
  def add_rule(conn, %{"plan_id" => plan_id} = params) do
    actor = get_req_header(conn, "x-actor-code") |> List.first("system")

    with {:ok, plan} <- Pricing.get_plan(plan_id),
         {:ok, rule} <- Pricing.create_rule(plan.id, rule_attrs(params), actor) do
      conn |> put_status(:created) |> json(rule_data(rule))
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "plan_not_found"})

      {:error, %Ecto.Changeset{} = cs} ->
        errors = Ecto.Changeset.traverse_errors(cs, fn {msg, _} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_failed", details: errors})
    end
  end

  # DELETE /internal/pricing-plans/:plan_id/rules/:rule_id
  def remove_rule(conn, %{"rule_id" => rule_id}) do
    case Pricing.delete_rule(rule_id) do
      {:ok, _rule} -> Response.ok(conn, %{deleted: true})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "rule_not_found"})
      {:error, _} -> conn |> put_status(:unprocessable_entity) |> json(%{error: "delete_failed"})
    end
  end

  # PATCH /internal/merchants/:merchant_code/pricing-plan
  def assign_plan(conn, %{"merchant_code" => merchant_code, "plan_id" => plan_id}) do
    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, plan} <- Pricing.assign_plan(merchant.id, plan_id) do
      Response.ok(conn, plan_summary(plan))
    else
      {:error, :plan_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "plan_not_found"})

      {:error, _} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "assign_failed"})
    end
  end

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

  defp plan_summary(plan) do
    %{
      id: plan.public_id,
      name: plan.name,
      version: plan.version,
      currency: plan.currency,
      fee_mode: plan.fee_mode,
      monthly_fee: plan.monthly_fee,
      effective_from: plan.effective_from
    }
  end

  defp rule_attrs(params) do
    ~w[method provider_code card_brand region amount_min amount_max
       percentage_bps fixed_amount minimum_fee maximum_fee rounding]
    |> Enum.flat_map(fn k ->
      case params[k] do
        nil -> []
        v -> [{k, v}]
      end
    end)
    |> Map.new()
  end

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
      specificity: rule.specificity,
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
