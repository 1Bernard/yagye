defmodule YagyeCoreWeb.Controllers.Public.ReceiptController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Checkout.Schemas.MerchantCheckoutConfig
  alias YagyeCore.Payments
  alias YagyeCore.Repo

  def show(conn, %{"public_id" => public_id}) do
    case fetch_receipt_data(public_id) do
      {:ok, data} ->
        conn
        |> put_resp_content_type("text/html")
        |> put_status(:ok)
        |> render(:show, data: data)

      {:error, _} ->
        conn
        |> put_resp_content_type("text/html")
        |> put_status(:not_found)
        |> text("Receipt not found.")
    end
  end

  defp fetch_receipt_data(public_id) do
    with {:ok, payment} <- Payments.get_payment(public_id),
         :ok <- ensure_succeeded(payment) do
      payment = Repo.preload(payment, [:customer, :merchant])
      checkout_config = Repo.get(MerchantCheckoutConfig, payment.merchant_id)

      {:ok,
       %{
         payment: payment,
         merchant: payment.merchant,
         customer: payment.customer,
         checkout_config: checkout_config
       }}
    end
  end

  defp ensure_succeeded(%{state: "succeeded"}), do: :ok
  defp ensure_succeeded(_), do: {:error, :not_succeeded}
end
