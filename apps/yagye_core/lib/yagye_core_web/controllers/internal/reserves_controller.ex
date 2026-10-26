defmodule YagyeCoreWeb.Controllers.Internal.ReservesController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  import Ecto.Query

  alias YagyeCore.Merchants
  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Repo
  alias YagyeCore.Reserves
  alias YagyeCore.Reserves.Schemas.{MerchantReserve, ReserveHold}
  alias YagyeCoreWeb.Response

  action_fallback(YagyeCoreWeb.FallbackController)

  # GET /internal/merchants/:merchant_code/reserves
  def index(conn, %{"merchant_code" => merchant_code} = params) do
    limit = parse_limit(params)
    offset = String.to_integer(params["offset"] || "0")

    with {:ok, merchant} <- Merchants.get_merchant(merchant_code) do
      reserves = Reserves.list_merchant_reserves(merchant.id)
      policy = current_policy(reserves)
      summary = aggregate_holds(merchant.id)

      base_query =
        from(h in ReserveHold, where: h.merchant_id == ^merchant.id)
        |> filter_holds_by_state(params["state"])
        |> filter_holds_by_reference(params["q"])
        |> filter_holds_from(params["from"])
        |> filter_holds_to(params["to"])

      total = Repo.one(from(h in base_query, select: count(h.id)))

      holds =
        from(h in base_query, order_by: [desc: h.held_at], limit: ^limit, offset: ^offset)
        |> Repo.all()
        |> Repo.preload(:payment)

      Response.ok(conn, %{
        policy: policy_data(policy),
        reserves: Enum.map(reserves, &policy_data/1),
        summary: summary,
        holds: Enum.map(holds, fn h -> hold_data(h, h.payment) end),
        meta: %{limit: limit, offset: offset, total: total}
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

  # GET /internal/merchants/:merchant_code/reserves/forecast
  def forecast(conn, %{"merchant_code" => merchant_code}) do
    with {:ok, merchant} <- Merchants.get_merchant(merchant_code) do
      now = DateTime.utc_now()
      d30 = DateTime.add(now, 30, :day)
      d60 = DateTime.add(now, 60, :day)
      d90 = DateTime.add(now, 90, :day)

      pending_holds =
        from(h in ReserveHold,
          where: h.merchant_id == ^merchant.id and h.state == "pending"
        )

      next_30 =
        Repo.one(
          from(h in pending_holds,
            where: h.release_at <= ^d30,
            select: coalesce(sum(h.amount), 0)
          )
        )

      next_60 =
        Repo.one(
          from(h in pending_holds,
            where: h.release_at > ^d30 and h.release_at <= ^d60,
            select: coalesce(sum(h.amount), 0)
          )
        )

      next_90 =
        Repo.one(
          from(h in pending_holds,
            where: h.release_at > ^d60 and h.release_at <= ^d90,
            select: coalesce(sum(h.amount), 0)
          )
        )

      beyond =
        Repo.one(
          from(h in pending_holds,
            where: h.release_at > ^d90,
            select: coalesce(sum(h.amount), 0)
          )
        )

      by_month =
        from(h in ReserveHold,
          where: h.merchant_id == ^merchant.id and h.state == "pending",
          group_by: fragment("date_trunc('month', ?)", h.release_at),
          order_by: fragment("date_trunc('month', ?)", h.release_at),
          select: {fragment("date_trunc('month', ?)", h.release_at), sum(h.amount)}
        )
        |> Repo.all()
        |> Enum.map(fn {month, amount} -> %{month: month, amount: amount} end)

      Response.ok(conn, %{
        next_30_days: next_30,
        next_31_60_days: next_60,
        next_61_90_days: next_90,
        beyond_90_days: beyond,
        by_month: by_month
      })
    end
  end

  # GET /internal/payments/:payment_id/reserve-hold
  def payment_hold(conn, %{"payment_id" => public_id}) do
    case Repo.get_by(Payment, public_id: public_id) do
      nil ->
        Response.not_found(conn)

      payment ->
        hold = Repo.get_by(ReserveHold, payment_id: payment.id)
        Response.ok(conn, hold && hold_data(hold, payment))
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

  defp parse_limit(%{"export" => "true"}), do: 10_000
  defp parse_limit(params), do: min(String.to_integer(params["limit"] || "50"), 200)

  defp current_policy(reserves) do
    Enum.find(reserves, &(&1.status == "active")) ||
      Enum.find(reserves, &(&1.status == "awaiting_merchant_ack")) ||
      Enum.find(reserves, &(&1.status == "pending_approval")) ||
      List.first(Enum.filter(reserves, &(&1.status == "inactive")))
  end

  defp filter_holds_by_state(query, state) when state in ~w[pending released drawn] do
    from(h in query, where: h.state == ^state)
  end

  defp filter_holds_by_state(query, _), do: query

  defp filter_holds_by_reference(query, q) when is_binary(q) and q != "" do
    from(h in query,
      join: p in Payment,
      on: p.id == h.payment_id,
      where: ilike(p.merchant_reference, ^"%#{q}%")
    )
  end

  defp filter_holds_by_reference(query, _), do: query

  defp filter_holds_from(query, from_date) when is_binary(from_date) do
    case Date.from_iso8601(from_date) do
      {:ok, d} -> from(h in query, where: h.held_at >= ^DateTime.new!(d, ~T[00:00:00], "Etc/UTC"))
      _ -> query
    end
  end

  defp filter_holds_from(query, _), do: query

  defp filter_holds_to(query, to_date) when is_binary(to_date) do
    case Date.from_iso8601(to_date) do
      {:ok, d} -> from(h in query, where: h.held_at <= ^DateTime.new!(d, ~T[23:59:59], "Etc/UTC"))
      _ -> query
    end
  end

  defp filter_holds_to(query, _), do: query

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

  defp hold_data(%ReserveHold{} = h, payment) do
    %{
      id: h.id,
      payment_id: h.payment_id,
      payment_public_id: payment && payment.public_id,
      payment_reference: payment && payment.merchant_reference,
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
