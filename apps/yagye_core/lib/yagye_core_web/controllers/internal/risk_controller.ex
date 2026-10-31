defmodule YagyeCoreWeb.Controllers.Internal.RiskController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Compliance
  alias YagyeCore.Risk
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  def list_flagged(conn, params) do
    opts = [
      decision: params["decision"],
      after: params["after"],
      limit: parse_limit(params["limit"])
    ]

    with {:ok, page} <- Risk.list_flagged(opts) do
      Response.ok(conn, %{
        object: "list",
        data: Enum.map(page.data, &render_flagged_payment/1),
        has_more: page.has_more,
        next: page.next
      })
    end
  end

  def show_case(conn, %{"payment_id" => payment_id}) do
    with {:ok, {payment, labels}} <- Risk.get_case(payment_id) do
      Response.ok(conn, %{
        object: "risk_case",
        payment: render_flagged_payment(payment),
        labels: Enum.map(labels, &render_label/1)
      })
    end
  end

  def flag(conn, %{"payment_id" => payment_id} = params) do
    flagged_by = params["flagged_by"] || "system"

    with {:ok, payment} <- Risk.flag_payment(payment_id, flagged_by) do
      Response.ok(conn, render_flagged_payment(payment))
    end
  end

  def dispose(conn, %{"payment_id" => payment_id} = params) do
    label = params["label"]
    dispositioned_by = params["dispositioned_by"]
    note = params["note"]

    with {:ok, risk_label} <- Risk.dispose_case(payment_id, label, dispositioned_by, note) do
      Response.ok(conn, render_label(risk_label))
    end
  end

  # ── Rendering ────────────────────────────────────────────────────────────────

  defp render_flagged_payment(payment) do
    %{
      object: "payment",
      id: payment.id,
      public_id: payment.public_id,
      merchant_id: payment.merchant_id,
      amount: payment.amount,
      currency: payment.currency,
      state: payment.state,
      method: payment.method,
      risk_score: payment.risk_score,
      risk_decision: payment.risk_decision,
      risk_flagged_at: payment.risk_flagged_at,
      inserted_at: payment.inserted_at
    }
  end

  defp render_label(label) do
    %{
      object: "risk_label",
      id: label.id,
      payment_id: label.payment_id,
      label: label.label,
      labelled_by: label.labelled_by,
      note: label.note,
      inserted_at: label.inserted_at
    }
  end

  def list_screening_hits(conn, params) do
    opts = [
      list_type: params["list_type"],
      limit: parse_limit(params["limit"]),
      after: params["after"]
    ]

    {hits, has_more, next} = Compliance.list_open_hits(opts)

    Response.ok(conn, %{
      object: "list",
      data: Enum.map(hits, &render_screening_hit/1),
      has_more: has_more,
      next: next && DateTime.to_iso8601(next)
    })
  end

  def dispose_hit(conn, %{"id" => hit_id} = params) do
    attrs = %{
      merchant_id: params["merchant_id"],
      status: params["status"],
      disposition_reason: params["disposition_reason"],
      dispositioned_by: params["dispositioned_by"]
    }

    with {:ok, hit} <- Compliance.disposition_hit(hit_id, attrs) do
      Response.ok(conn, render_screening_hit(hit))
    end
  end

  # ── Rendering ────────────────────────────────────────────────────────────────

  defp render_screening_hit(hit) do
    %{
      object: "screening_hit",
      id: hit.id,
      merchant_id: hit.merchant_id,
      subject_type: hit.subject_type,
      list_type: hit.list_type,
      list_source: hit.list_source,
      matched_name: hit.matched_name,
      match_score: hit.match_score,
      status: hit.status,
      raised_by: hit.raised_by,
      dispositioned_by: hit.dispositioned_by,
      dispositioned_at: hit.dispositioned_at,
      inserted_at: hit.inserted_at
    }
  end

  defp parse_limit(nil), do: 25
  defp parse_limit(l) when is_integer(l), do: min(l, 100)
  defp parse_limit(l), do: l |> Integer.parse() |> elem(0) |> min(100)
end
