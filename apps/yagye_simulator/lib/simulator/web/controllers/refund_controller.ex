defmodule Simulator.Web.Controllers.RefundController do
  use Phoenix.Controller, formats: [:json]

  alias Simulator.Refunds

  def create(conn, %{"ref" => charge_ref} = params) do
    account = conn.assigns.current_account

    case parse_amount(params["amount_minor"]) do
      {:error, message} ->
        conn |> put_status(422) |> json(%{error: message})

      {:ok, amount} ->
        do_create_refund(conn, account, charge_ref, amount)
    end
  end

  defp do_create_refund(conn, account, charge_ref, amount) do
    case Refunds.create_refund(account, charge_ref, %{amount_minor: amount}) do
      {:ok, refund} ->
        conn |> put_status(201) |> json(render_refund(refund))

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "charge_not_found"})

      {:error, {:not_refundable, state}} ->
        conn |> put_status(422) |> json(%{error: "not_refundable", charge_state: state})

      {:error, :amount_exceeds_original} ->
        conn |> put_status(422) |> json(%{error: "amount_exceeds_original"})

      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: inspect(reason)})
    end
  end

  defp parse_amount(nil), do: {:error, "amount_minor is required"}
  defp parse_amount(v) when is_integer(v) and v > 0, do: {:ok, v}
  defp parse_amount(_), do: {:error, "amount_minor must be a positive integer"}

  def show(conn, %{"ref" => ref}) do
    case Refunds.get_by_ref(ref) do
      {:ok, refund} -> json(conn, render_refund(refund))
      {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "refund_not_found"})
    end
  end

  defp render_refund(refund) do
    %{
      refund_ref: refund.refund_ref,
      charge_id: refund.charge_id,
      amount_minor: refund.amount_minor,
      currency: refund.currency,
      state: refund.state,
      fee_minor: refund.fee_minor,
      refund_arn: refund.refund_arn,
      failure_code: refund.failure_code,
      created_at: refund.created_at
    }
  end
end
