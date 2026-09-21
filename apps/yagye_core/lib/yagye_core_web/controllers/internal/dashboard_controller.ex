defmodule YagyeCoreWeb.Controllers.Internal.DashboardController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Dashboard
  alias YagyeCore.Merchants
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  def ops_summary(conn, _params) do
    summary = Dashboard.ops_summary()
    Response.ok(conn, render_ops_summary(summary))
  end

  def merchant_settlement(conn, %{"merchant_code" => merchant_code}) do
    with {:ok, merchant} <- Merchants.get_merchant(merchant_code) do
      summary = Dashboard.merchant_settlement_summary(merchant.id)
      Response.ok(conn, render_merchant_settlement(summary))
    end
  end

  # ── Rendering ────────────────────────────────────────────────────────────────

  defp render_ops_summary(%{
         float_balances: floats,
         merchant_payables: payables,
         pipeline: pipeline,
         failed_disbursements: failed
       }) do
    %{
      object: "ops_dashboard",
      float_balances: Enum.map(floats, &render_float_balance/1),
      merchant_payables: Enum.map(payables, &render_merchant_payable/1),
      settlement_pipeline: pipeline,
      failed_disbursements: Enum.map(failed, &render_failed_batch/1)
    }
  end

  defp render_float_balance(b) do
    %{
      provider_code: b.provider_code,
      provider_name: b.provider_name,
      currency: b.currency,
      mode: b.mode,
      balance: b.balance
    }
  end

  defp render_merchant_payable(b) do
    %{
      merchant_id: b.merchant_id,
      merchant_name: b.merchant_name,
      currency: b.currency,
      mode: b.mode,
      balance: b.balance
    }
  end

  defp render_failed_batch(b) do
    %{
      id: b.id,
      merchant_id: b.merchant_id,
      state: b.state,
      currency: b.currency,
      gross_amount: b.gross_amount,
      mode: b.mode,
      inserted_at: b.inserted_at
    }
  end

  defp render_merchant_settlement(%{
         payable_balances: payables,
         destination: dest,
         recent_batches: batches
       }) do
    %{
      object: "merchant_settlement_summary",
      payable_balances: payables,
      destination: dest,
      recent_batches: Enum.map(batches, &render_batch/1)
    }
  end

  defp render_batch(b) do
    %{
      id: b.id,
      state: b.state,
      state_label: b.state_label,
      currency: b.currency,
      gross_amount: b.gross_amount,
      mode: b.mode,
      bank_dispatch_ref: b.bank_dispatch_ref,
      inserted_at: b.inserted_at
    }
  end
end
