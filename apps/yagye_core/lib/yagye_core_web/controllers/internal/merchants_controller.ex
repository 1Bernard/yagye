defmodule YagyeCoreWeb.Controllers.Internal.MerchantsController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.{Merchants, Payments}
  alias YagyeCoreWeb.Controllers.Payments.PaymentJSON
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  @doc """
  Ops-initiated full KYB approval for a merchant.
  Enforces the 25% UBO screening threshold: returns 422/unscreened_ubos
  if any beneficial owner with ≥25% ownership has not been cleared.
  """
  def kyb_approve(conn, %{"merchant_code" => merchant_code} = params) do
    with {:ok, approved_by} <- require_actor(params["approved_by"]),
         {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, {merchant, _event}} <- Merchants.approve(merchant.public_id, approved_by) do
      Response.ok(conn, %{
        object: "merchant",
        id: merchant.public_id,
        status: merchant.status,
        kyb_tier: merchant.kyb_tier,
        approved_by: approved_by
      })
    end
  end

  def kyb_start_review(conn, %{"merchant_code" => merchant_code} = params) do
    with {:ok, reviewed_by} <- require_param(params["reviewed_by"], "reviewed_by"),
         {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, {_merchant, _event}} <- Merchants.start_review(merchant.public_id, reviewed_by) do
      Response.ok(conn, %{object: "merchant", id: merchant.public_id, status: "under_review"})
    end
  end

  def enable_sandbox(conn, %{"merchant_code" => merchant_code} = params) do
    with {:ok, granted_by} <- require_param(params["granted_by"], "granted_by"),
         {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, :enabled} <- Merchants.enable_sandbox_mode(merchant.id, granted_by) do
      Response.ok(conn, %{
        object: "merchant",
        id: merchant.public_id,
        sandbox_enabled: true,
        granted_by: granted_by
      })
    end
  end

  def suspend(conn, %{"merchant_code" => merchant_code} = params) do
    with {:ok, suspended_by} <- require_param(params["suspended_by"], "suspended_by"),
         {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, updated} <- Merchants.suspend_merchant(merchant.id, suspended_by) do
      Response.ok(conn, %{
        object: "merchant",
        id: updated.public_id,
        activity_state: updated.activity_state,
        suspended_by: suspended_by
      })
    end
  end

  def reactivate(conn, %{"merchant_code" => merchant_code} = params) do
    reinstated_by = params["reactivated_by"] || params["reinstated_by"]

    with {:ok, actor} <- require_param(reinstated_by, "reactivated_by"),
         {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, updated} <- Merchants.unsuspend_merchant(merchant.id, actor) do
      Response.ok(conn, %{
        object: "merchant",
        id: updated.public_id,
        activity_state: updated.activity_state,
        reactivated_by: actor
      })
    end
  end

  def payment_events(conn, %{"id" => payment_public_id}) do
    with {:ok, payment} <- Payments.get_payment(payment_public_id),
         {:ok, events} <- Payments.list_events(payment.id) do
      Response.ok(conn, PaymentJSON.event_list(events))
    end
  end

  defp require_actor(v), do: require_param(v, "approved_by")

  defp require_param(nil, name), do: {:error, {:missing_param, name}}
  defp require_param("", name), do: {:error, {:missing_param, name}}
  defp require_param(v, _name), do: {:ok, v}
end
