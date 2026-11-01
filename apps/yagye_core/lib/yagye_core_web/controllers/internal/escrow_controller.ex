defmodule YagyeCoreWeb.Controllers.Internal.EscrowController do
  use YagyeCoreWeb, :controller

  action_fallback YagyeCoreWeb.FallbackController

  alias YagyeCore.Escrow
  alias YagyeCore.Escrow.Schemas.EscrowHold
  alias YagyeCore.Payments.Schemas.PaymentAttempt
  alias YagyeCore.Repo
  alias YagyeCoreWeb.Response

  def show(conn, %{"public_id" => public_id}) do
    with {:ok, hold} <- Escrow.get_hold(public_id) do
      Response.ok(conn, hold_data(hold))
    end
  end

  def index(conn, %{"merchant_id" => merchant_id} = params) do
    state = Map.get(params, "state")
    opts = if state, do: [state: state], else: []
    holds = Escrow.list_holds(merchant_id, opts)
    Response.ok(conn, Enum.map(holds, &hold_data/1))
  end

  def confirm_release(conn, %{"public_id" => public_id, "attempt_id" => attempt_id}) do
    attempt = Repo.get!(PaymentAttempt, attempt_id)

    with {:ok, hold} <- Escrow.confirm_release(public_id, attempt) do
      Response.ok(conn, hold_data(hold))
    end
  end

  def open_dispute(conn, %{"public_id" => public_id} = params) do
    actor = Map.get(params, "actor", "buyer")
    note = Map.get(params, "note")

    with {:ok, hold} <- Escrow.open_dispute(public_id, actor, note) do
      Response.ok(conn, hold_data(hold))
    end
  end

  def resolve_dispute(conn, %{"public_id" => public_id} = params) do
    outcome = Map.get(params, "outcome")
    actor = Map.get(params, "actor", "ops")
    note = Map.get(params, "note")
    attempt_id = Map.get(params, "attempt_id")
    attempt = Repo.get!(PaymentAttempt, attempt_id)

    with {:ok, hold} <- Escrow.resolve_dispute(public_id, outcome, actor, note, attempt) do
      Response.ok(conn, hold_data(hold))
    end
  end

  defp hold_data(%EscrowHold{} = h) do
    %{
      id: h.id,
      public_id: h.public_id,
      payment_id: h.payment_id,
      payment_link_id: h.payment_link_id,
      merchant_id: h.merchant_id,
      amount: h.amount,
      currency: h.currency,
      mode: h.mode,
      state: h.state,
      buyer_confirmed_at: h.buyer_confirmed_at,
      auto_release_at: h.auto_release_at,
      dispute_window_ends_at: h.dispute_window_ends_at,
      released_at: h.released_at,
      refunded_at: h.refunded_at,
      inserted_at: h.inserted_at
    }
  end
end
