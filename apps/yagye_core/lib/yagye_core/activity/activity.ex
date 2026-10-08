defmodule YagyeCore.Activity do
  @moduledoc "Cross-domain activity feed — fan-out merge across payments, settlements, disputes, and refunds."

  import Ecto.Query

  alias YagyeCore.Disputes.Schemas.{Dispute, Refund}
  alias YagyeCore.Payments.Schemas.{Payment, PaymentEvent}
  alias YagyeCore.Repo
  alias YagyeCore.Settlement.Schemas.SettlementBatch

  @default_limit 50
  @all_domains ~w[payment settlement dispute refund]

  # Only terminal/significant payment events — intermediate processing steps are noise
  @significant_payment_events ~w[
    payment.succeeded payment.failed payment.cancelled
    payment.indeterminate payment.disputed payment.refunded payment.chargebacked
  ]

  @doc """
  Returns a time-ordered list of activity events for a merchant.

  Options:
    - `:limit`   — max events returned (default 50, capped at 100)
    - `:before`  — `DateTime` cursor; only events strictly before this are returned
    - `:domains` — list of domain strings to include (default: all)
  """
  def list_for_merchant(merchant_id, opts \\ []) do
    limit = min(Keyword.get(opts, :limit, @default_limit), 100)
    before = Keyword.get(opts, :before)
    domains = Keyword.get(opts, :domains, @all_domains) |> Enum.filter(&(&1 in @all_domains))
    domains = if domains == [], do: @all_domains, else: domains

    events =
      domains
      |> Enum.flat_map(fn
        "payment" -> payment_events(merchant_id, before, limit)
        "settlement" -> settlement_events(merchant_id, before, limit)
        "dispute" -> dispute_events(merchant_id, before, limit)
        "refund" -> refund_events(merchant_id, before, limit)
      end)
      |> Enum.sort_by(& &1.occurred_at, {:desc, DateTime})
      |> Enum.take(limit)

    {:ok, events}
  end

  # ── Payment events ────────────────────────────────────────────────────────

  defp payment_events(merchant_id, before, limit) do
    base =
      Payment
      |> where([p], p.merchant_id == ^merchant_id)
      |> join(:inner, [p], pe in PaymentEvent, on: pe.payment_id == p.id)
      |> where([_p, pe], pe.event_type in @significant_payment_events)
      |> order_by([_p, pe], desc: pe.occurred_at)
      |> limit(^limit)
      |> select([p, pe], %{
        domain: "payment",
        event_type: pe.event_type,
        resource_type: "payment",
        resource_id: p.public_id,
        resource_ref: p.merchant_reference,
        occurred_at: pe.occurred_at,
        metadata: pe.payload
      })

    base = if before, do: where(base, [_p, pe], pe.occurred_at < ^before), else: base
    Repo.all(base)
  end

  # ── Settlement events ─────────────────────────────────────────────────────

  defp settlement_events(merchant_id, before, limit) do
    base =
      SettlementBatch
      |> where([sb], sb.merchant_id == ^merchant_id)
      |> order_by([sb], desc: sb.inserted_at)
      |> limit(^limit)

    base = if before, do: where(base, [sb], sb.inserted_at < ^before), else: base

    base
    |> Repo.all()
    |> Enum.map(fn sb ->
      %{
        domain: "settlement",
        event_type:
          if(sb.state == "settled", do: "settlement.settled", else: "settlement.created"),
        resource_type: "settlement_batch",
        resource_id: to_string(sb.id),
        resource_ref: "#{sb.currency} · #{period_label(sb)}",
        occurred_at: sb.settled_at || sb.inserted_at,
        metadata: %{
          "net_amount" => sb.net_amount,
          "gross_amount" => sb.gross_amount,
          "currency" => sb.currency,
          "payment_count" => sb.payment_count,
          "state" => sb.state
        }
      }
    end)
  end

  # ── Dispute events ────────────────────────────────────────────────────────

  defp dispute_events(merchant_id, before, limit) do
    base =
      Dispute
      |> where([d], d.merchant_id == ^merchant_id)
      |> order_by([d], desc: d.inserted_at)
      |> limit(^limit)

    base = if before, do: where(base, [d], d.inserted_at < ^before), else: base

    base
    |> Repo.all()
    |> Enum.map(fn d ->
      %{
        domain: "dispute",
        event_type: if(d.stage == "resolved", do: "dispute.resolved", else: "dispute.opened"),
        resource_type: "dispute",
        resource_id: d.public_id,
        resource_ref: d.public_id,
        occurred_at: d.inserted_at,
        metadata: %{
          "amount" => d.amount,
          "currency" => d.currency,
          "reason" => d.reason,
          "stage" => d.stage,
          "outcome" => d.outcome
        }
      }
    end)
  end

  # ── Refund events ─────────────────────────────────────────────────────────

  defp refund_events(merchant_id, before, limit) do
    base =
      Refund
      |> where([r], r.merchant_id == ^merchant_id)
      |> order_by([r], desc: r.inserted_at)
      |> limit(^limit)

    base = if before, do: where(base, [r], r.inserted_at < ^before), else: base

    base
    |> Repo.all()
    |> Enum.map(fn r ->
      %{
        domain: "refund",
        event_type: "refund.#{r.state}",
        resource_type: "refund",
        resource_id: r.public_id,
        resource_ref: r.public_id,
        occurred_at: r.inserted_at,
        metadata: %{
          "amount" => r.amount,
          "currency" => r.currency,
          "reason" => r.reason,
          "state" => r.state
        }
      }
    end)
  end

  defp period_label(batch) do
    ts = batch.period_end || batch.inserted_at
    Calendar.strftime(ts, "%b %Y")
  end
end
