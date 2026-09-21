defmodule YagyeCoreWeb.Controllers.Internal.SettlementControlsController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Settlement

  def show(conn, %{"merchant_id" => merchant_id}) do
    case Settlement.get_settlement_controls(merchant_id) do
      nil ->
        json(conn, %{approval_threshold: nil, approver_user_codes: []})

      controls ->
        json(conn, %{
          approval_threshold: controls.approval_threshold,
          approver_user_codes: controls.approver_user_codes
        })
    end
  end

  def upsert(conn, %{"merchant_id" => merchant_id} = params) do
    attrs =
      %{
        approval_threshold: params["approval_threshold"],
        approver_user_codes: params["approver_user_codes"] || [],
        settlement_frequency: params["settlement_frequency"],
        settlement_day: params["settlement_day"],
        settlement_msisdn: params["settlement_msisdn"],
        settlement_bank_code: params["settlement_bank_code"],
        settlement_account_number: params["settlement_account_number"],
        settlement_account_name: params["settlement_account_name"],
        updated_by: params["updated_by"] || "portal"
      }
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    case Settlement.upsert_settlement_controls(merchant_id, attrs) do
      {:ok, controls} ->
        json(conn, %{
          approval_threshold: controls.approval_threshold,
          approver_user_codes: controls.approver_user_codes,
          settlement_msisdn: controls.settlement_msisdn,
          settlement_bank_code: controls.settlement_bank_code,
          settlement_account_number: controls.settlement_account_number,
          settlement_account_name: controls.settlement_account_name
        })

      {:error, cs} ->
        conn
        |> put_status(422)
        |> json(%{errors: format_errors(cs)})
    end
  end

  defp format_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
  end
end
