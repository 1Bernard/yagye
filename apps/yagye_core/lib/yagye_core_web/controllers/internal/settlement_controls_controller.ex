defmodule YagyeCoreWeb.Controllers.Internal.SettlementControlsController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  action_fallback YagyeCoreWeb.FallbackController

  alias YagyeCore.Settlement

  def show(conn, %{"merchant_id" => merchant_id}) do
    case Settlement.get_settlement_controls(merchant_id) do
      nil ->
        json(conn, default_controls())

      controls ->
        json(conn, serialize_controls(controls))
    end
  end

  def upsert(conn, %{"merchant_id" => merchant_id} = params) do
    attrs =
      %{
        approval_threshold: params["approval_threshold"],
        approver_user_codes: params["approver_user_codes"] || [],
        settlement_msisdn: params["settlement_msisdn"],
        settlement_bank_code: params["settlement_bank_code"],
        settlement_account_number: params["settlement_account_number"],
        settlement_account_name: params["settlement_account_name"],
        settlement_delay_days: params["settlement_delay_days"],
        minimum_payout_pesewas: params["minimum_payout_pesewas"],
        settlement_frequency: params["settlement_frequency"],
        reserve_rate_bps: params["reserve_rate_bps"],
        reserve_release_days: params["reserve_release_days"],
        early_settlement_enabled: params["early_settlement_enabled"],
        on_hold: params["on_hold"],
        hold_reason: params["hold_reason"],
        updated_by: params["updated_by"] || "portal"
      }
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    case Settlement.upsert_settlement_controls(merchant_id, attrs) do
      {:ok, controls} ->
        json(conn, serialize_controls(controls))

      {:error, cs} ->
        conn
        |> put_status(422)
        |> json(%{errors: format_errors(cs)})
    end
  end

  defp serialize_controls(controls) do
    %{
      approval_threshold: controls.approval_threshold,
      approver_user_codes: controls.approver_user_codes,
      settlement_msisdn: controls.settlement_msisdn,
      settlement_bank_code: controls.settlement_bank_code,
      settlement_account_number: controls.settlement_account_number,
      settlement_account_name: controls.settlement_account_name,
      settlement_delay_days: controls.settlement_delay_days,
      minimum_payout_pesewas: controls.minimum_payout_pesewas,
      settlement_frequency: controls.settlement_frequency,
      reserve_rate_bps: controls.reserve_rate_bps,
      reserve_release_days: controls.reserve_release_days,
      early_settlement_enabled: controls.early_settlement_enabled,
      on_hold: controls.on_hold,
      hold_reason: controls.hold_reason
    }
  end

  defp default_controls do
    %{
      approval_threshold: nil,
      approver_user_codes: [],
      settlement_msisdn: nil,
      settlement_bank_code: nil,
      settlement_account_number: nil,
      settlement_account_name: nil,
      settlement_delay_days: 1,
      minimum_payout_pesewas: 5_000,
      settlement_frequency: "daily",
      reserve_rate_bps: 0,
      reserve_release_days: 90,
      early_settlement_enabled: false,
      on_hold: false,
      hold_reason: nil
    }
  end
end
