defmodule YagyeCoreWeb.Controllers.Internal.MerchantsController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Merchants
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
         {:ok, {merchant, _event}} <- Merchants.approve(merchant.id, approved_by) do
      Response.ok(conn, %{
        object: "merchant",
        id: merchant.public_id,
        status: merchant.status,
        kyb_tier: merchant.kyb_tier,
        approved_by: approved_by
      })
    end
  end

  defp require_actor(nil), do: {:error, {:missing_param, "approved_by"}}
  defp require_actor(""), do: {:error, {:missing_param, "approved_by"}}
  defp require_actor(v), do: {:ok, v}
end
