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
      reserves = Reserves.list_merchant_reserves(merchant.id)

      policy =
        Enum.find(reserves, &(&1.status == "active")) ||
          Enum.find(reserves, &(&1.status == "awaiting_merchant_ack")) ||
          Enum.find(reserves, &(&1.status == "pending_approval")) ||
          List.first(Enum.filter(reserves, &(&1.status == "inactive")))

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
        reserves: Enum.map(reserves, &policy_data/1),
        summary: summary,
        holds: Enum.map(holds, &hold_data/1),
        meta: %{limit: limit, offset: offset, total: summary.total_count}
      })
    end
  end

  # POST /internal/merchants/:merchant_code/reserves
  def create_policy(conn, %{"merchant_code" => merchant_code} = params) do
    with {:ok, created_by} <- require_param(params["created_by"], "created_by"),
         {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, reserve} <-
           Reserves.create_policy(merchant.id, %{
             mode: params["mode"] || "live",
             kind: params["kind"],
             percentage_bps:
               params["percentage_bps"] &&
                 String.to_integer(to_string(params["percentage_bps"])),
             fixed_amount:
               params["fixed_amount"] &&
                 String.to_integer(to_string(params["fixed_amount"])),
             currency: params["currency"] || merchant.default_currency,
             hold_days: params["hold_days"] && String.to_integer(to_string(params["hold_days"])),
             reason: params["reason"],
             created_by: created_by
           }) do
      Response.created(conn, reserve_data(reserve))
    end
  end

  # POST /internal/reserves/:id/approve
  def approve_policy(conn, %{"id" => id} = params) do
    with {:ok, approved_by} <- require_param(params["approved_by"], "approved_by"),
         {:ok, reserve} <- fetch_reserve(id),
         {:ok, approved} <- Reserves.approve_policy(reserve, approved_by) do
      Response.ok(conn, reserve_data(approved))
    end
  end

  # POST /internal/reserves/:id/deactivate
  def deactivate_policy(conn, %{"id" => id}) do
    with {:ok, reserve} <- fetch_reserve(id),
         {:ok, deactivated} <- Reserves.deactivate_policy(reserve) do
      Response.ok(conn, reserve_data(deactivated))
    end
  end

  # POST /internal/reserves/:id/acknowledge
  def acknowledge_policy(conn, %{"id" => id} = params) do
    with {:ok, acknowledged_by} <- require_param(params["acknowledged_by"], "acknowledged_by"),
         {:ok, reserve} <- fetch_reserve(id),
         {:ok, acknowledged} <- Reserves.acknowledge_policy(reserve, acknowledged_by) do
      Response.ok(conn, reserve_data(acknowledged))
    end
  end

  # ── Private ───────────────────────────────────────────────────────────────

  defp require_param(nil, name), do: {:error, {:missing_param, name}}
  defp require_param("", name), do: {:error, {:missing_param, name}}
  defp require_param(v, _name), do: {:ok, v}

  defp fetch_reserve(id) do
    case Repo.get(MerchantReserve, id) do
      nil -> {:error, :not_found}
      reserve -> {:ok, reserve}
    end
  end

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

  defp reserve_data(%MerchantReserve{} = r), do: policy_data(r)

  defp policy_data(nil), do: nil

  defp policy_data(%MerchantReserve{} = p) do
    %{
      id: p.id,
      status: p.status,
      kind: p.kind,
      percentage_bps: p.percentage_bps,
      fixed_amount: p.fixed_amount,
      currency: p.currency,
      hold_days: p.hold_days,
      mode: p.mode,
      active: p.active,
      reason: p.reason,
      created_by: p.created_by,
      approved_by: p.approved_by,
      acknowledged_by: p.acknowledged_by,
      acknowledged_at: p.acknowledged_at,
      notice_sent_at: p.notice_sent_at,
      auto_activates_at: p.auto_activates_at,
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
