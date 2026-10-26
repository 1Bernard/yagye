defmodule YagyeCoreWeb.Controllers.Internal.RefundsController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  action_fallback YagyeCoreWeb.FallbackController

  alias YagyeCore.{Disputes, Payments}

  # POST /internal/payments/:payment_id/refunds
  # Used by the portal to initiate a merchant-requested refund via service token.
  def create(conn, %{"payment_id" => payment_public_id} = params) do
    amount =
      case params["amount"] do
        nil -> nil
        v -> String.to_integer(to_string(v))
      end

    attrs = %{
      amount: amount,
      reason: params["reason"] || "requested_by_merchant",
      initiated_by: params["initiated_by"]
    }

    with {:ok, payment} <- Payments.get_payment(payment_public_id),
         {:ok, {refund, _payment}} <- Disputes.create_refund(payment, attrs) do
      conn
      |> put_status(201)
      |> json(%{
        id: refund.public_id,
        payment_id: payment_public_id,
        amount: refund.amount,
        currency: refund.currency,
        reason: refund.reason,
        state: refund.state
      })
    else
      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: %{code: "payment_not_found", message: "Payment not found."}})

      {:error, {:not_refundable, state}} ->
        conn
        |> put_status(422)
        |> json(%{
          error: %{
            code: "not_refundable",
            message: "This payment cannot be refunded (current state: #{state})."
          }
        })

      {:error, :insufficient_balance} ->
        conn
        |> put_status(422)
        |> json(%{
          error: %{
            code: "insufficient_balance",
            message: "Insufficient merchant balance to cover this refund."
          }
        })

      {:error, :amount_required} ->
        conn
        |> put_status(422)
        |> json(%{error: %{code: "amount_required", message: "Refund amount is required."}})

      {:error, :amount_exceeds_original} ->
        conn
        |> put_status(422)
        |> json(%{
          error: %{
            code: "amount_exceeds_original",
            message: "Refund amount cannot exceed the remaining refundable amount."
          }
        })

      {:error, :window_expired} ->
        conn
        |> put_status(422)
        |> json(%{
          error: %{
            code: "window_expired",
            message: "This payment is outside the refund window for this merchant."
          }
        })

      {:error, :partial_refunds_disabled} ->
        conn
        |> put_status(422)
        |> json(%{
          error: %{
            code: "partial_refunds_disabled",
            message: "Partial refunds are not enabled for this merchant."
          }
        })

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: %{code: "refund_failed", message: inspect(reason)}})
    end
  end
end
