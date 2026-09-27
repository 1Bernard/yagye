defmodule YagyeCoreWeb.Controllers.Internal.ReservesController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  import Ecto.Query

  alias YagyeCore.Merchants
  alias YagyeCore.Repo
  alias YagyeCore.Reserves
  alias YagyeCore.Reserves.Schemas.{MerchantReserve, ReserveHold}
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  # GET /internal/merchants/:merchant_code/reserves
  def index(conn, %{"merchant_code" => merchant_code} = params) do
    limit = min(String.to_integer(params["limit"] || "50"), 200)
    offset = String.to_integer(params["offset"] || "0")

    with {:ok, merchant} <- Merchants.get_merchant(merchant_code) do
      policy =
        Reserves.reserve_policy_for(merchant.id, merchant.default_currency, "live") ||
          Reserves.reserve_policy_for(merchant.id, merchant.default_currency, "sandbox")

      summary = aggregate_holds(merchant.id)

      holds =
        from(h in ReserveHold,
          where: h.merchant_id == ^merchant.id,
          order_by: [desc: h.held_at],
          limit: ^limit,
          offset: ^offset
        )
        |> Repo.all()

      Response.ok(conn, %{
        policy: policy_data(policy),
        summary: summary,
        holds: Enum.map(holds, &hold_data/1),
        meta: %{limit: limit, offset: offset, total: summary.total_count}
      })
    end
  end

  # ── Private ───────────────────────────────────────────────────────────────

  defp aggregate_holds(merchant_id) do
    result =
      from(h in ReserveHold,
        where: h.merchant_id == ^merchant_id,
        group_by: h.state,
        select: {h.state, count(h.id), coalesce(sum(h.amount), 0)}
      )
      |> Repo.all()
      |> Map.new(fn {state, count, amount} -> {state, %{count: count, amount: amount}} end)

    pending = result["pending"] || %{count: 0, amount: 0}
    released = result["released"] || %{count: 0, amount: 0}
    drawn = result["drawn"] || %{count: 0, amount: 0}

    %{
      pending_amount: pending.amount,
      pending_count: pending.count,
      released_amount: released.amount,
      released_count: released.count,
      drawn_amount: drawn.amount,
      drawn_count: drawn.count,
      total_count: pending.count + released.count + drawn.count
    }
  end

  defp policy_data(nil), do: nil

  defp policy_data(%MerchantReserve{} = p) do
    %{
      id: p.id,
      kind: p.kind,
      percentage_bps: p.percentage_bps,
      fixed_amount: p.fixed_amount,
      currency: p.currency,
      hold_days: p.hold_days,
      mode: p.mode,
      active: p.active,
      created_by: p.created_by,
      approved_by: p.approved_by,
      inserted_at: p.inserted_at
    }
  end

  defp hold_data(%ReserveHold{} = h) do
    %{
      id: h.id,
      payment_id: h.payment_id,
      amount: h.amount,
      currency: h.currency,
      state: h.state,
      held_at: h.held_at,
      release_at: h.release_at,
      released_at: h.released_at,
      drawn_at: h.drawn_at
    }
  end
end
