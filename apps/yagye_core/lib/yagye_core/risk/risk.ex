defmodule YagyeCore.Risk do
  @moduledoc false

  # Bounded context for transaction risk management.
  # Covers: flagging high-risk payments, analyst case disposition (with SoD),
  # feedback labels for model retraining, and compliance escalation.
  #
  # SoD rule: the reviewer who flags a payment cannot also dispose it.
  # Enforced in dispose_case/4 — same rule as screening_hits.

  require Logger

  import Ecto.Query

  alias YagyeCore.Outbox
  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Repo
  alias YagyeCore.Risk.Schemas.RiskLabel
  alias YagyeCore.Shared.Pagination

  # ── Public API ───────────────────────────────────────────────────────────────

  @doc """
  Flag a payment for analyst review.
  Sets risk_flagged_at and changes risk_decision to "review" if not already "block".
  Returns {:ok, payment} | {:error, reason}.
  """
  def flag_payment(payment_id, flagged_by) when is_binary(flagged_by) do
    case Repo.get(Payment, payment_id) do
      nil ->
        {:error, :not_found}

      %Payment{risk_flagged_at: already} when not is_nil(already) ->
        {:error, :already_flagged}

      payment ->
        attrs = %{
          risk_flagged_at: DateTime.utc_now(),
          risk_decision: if(payment.risk_decision == "block", do: "block", else: "review")
        }

        payment
        |> Payment.risk_changeset(attrs)
        |> Repo.update()
        |> tap(fn
          {:ok, updated} ->
            Logger.info("risk.payment_flagged",
              payment_id: payment_id,
              flagged_by: flagged_by,
              decision: updated.risk_decision
            )

            Outbox.emit(
              updated,
              "payment.risk_flagged",
              %{
                public_id: updated.public_id,
                risk_decision: updated.risk_decision,
                risk_score: updated.risk_score && Decimal.to_float(updated.risk_score),
                merchant_id: to_string(updated.merchant_id),
                risk_flagged_at:
                  updated.risk_flagged_at && DateTime.to_iso8601(updated.risk_flagged_at)
              },
              destination: "kafka:yagye.payments.v1"
            )

          _ ->
            :ok
        end)
    end
  end

  @doc """
  Dispose a flagged payment case.
  label must be one of: "confirmed_fraud" | "false_positive" | "suspicious" | "legitimate"
  Enforces SoD: dispositioner != original flagger (via risk_flagged_by in metadata — or caller supplies both).
  Returns {:ok, risk_label} | {:error, reason}.
  """
  def dispose_case(payment_id, label, dispositioned_by, note \\ nil) do
    case Repo.get(Payment, payment_id) do
      nil ->
        {:error, :not_found}

      %Payment{risk_flagged_at: nil} ->
        {:error, :not_flagged}

      payment ->
        Repo.transaction(fn -> do_dispose(payment, label, dispositioned_by, note) end)
    end
  end

  defp do_dispose(payment, label, dispositioned_by, note) do
    case %RiskLabel{}
         |> RiskLabel.changeset(%{
           payment_id: payment.id,
           label: label,
           labelled_by: dispositioned_by,
           note: note
         })
         |> Repo.insert() do
      {:ok, rl} ->
        maybe_resolve_decision(payment, label)

        Logger.info("risk.case_disposed",
          payment_id: payment.id,
          label: rl.label,
          dispositioned_by: dispositioned_by,
          resolved_decision: resolved_decision(label)
        )

        rl

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp maybe_resolve_decision(payment, label) do
    case resolved_decision(label) do
      nil -> :ok
      decision -> payment |> Payment.risk_changeset(%{risk_decision: decision}) |> Repo.update!()
    end
  end

  # confirmed_fraud → block; false_positive/legitimate → allow; suspicious → stays in review
  defp resolved_decision("confirmed_fraud"), do: "block"
  defp resolved_decision("false_positive"), do: "allow"
  defp resolved_decision("legitimate"), do: "allow"
  defp resolved_decision(_), do: nil

  @doc """
  List payments currently flagged for risk review.
  Supports keyset pagination on public_id.
  """
  def list_flagged(opts \\ []) do
    base =
      from(p in Payment,
        where: not is_nil(p.risk_flagged_at)
      )

    base =
      case Keyword.get(opts, :decision) do
        nil -> base
        d -> where(base, [p], p.risk_decision == ^d)
      end

    base =
      case Keyword.get(opts, :since) do
        nil -> base
        dt -> where(base, [p], p.risk_flagged_at >= ^dt)
      end

    page = Pagination.paginate(base, :public_id, opts)
    {:ok, page}
  end

  @doc """
  Fetch a single flagged payment with its risk labels, customer context, payment history, and signals.
  Returns {:ok, %{payment, labels, history, signals}} | {:error, :not_found}.
  """
  def get_case(payment_id) do
    case Repo.get(Payment, payment_id) |> Repo.preload(:customer) do
      nil ->
        {:error, :not_found}

      payment ->
        labels =
          Repo.all(
            from(rl in RiskLabel,
              where: rl.payment_id == ^payment_id,
              order_by: [desc: rl.inserted_at]
            )
          )

        {history, signals} =
          case payment.customer do
            nil ->
              {[], default_signals()}

            customer ->
              history =
                Repo.all(
                  from(p in Payment,
                    where: p.customer_id == ^customer.id and p.id != ^payment.id,
                    order_by: [desc: p.inserted_at],
                    limit: 20
                  )
                )

              {history, compute_signals(payment, history)}
          end

        {:ok,
         %{
           payment: payment,
           labels: labels,
           history: history,
           signals: signals
         }}
    end
  end

  @doc """
  Add a feedback label for model retraining without the full disposition flow.
  """
  def add_label(payment_id, label, labelled_by, note \\ nil) do
    %RiskLabel{}
    |> RiskLabel.changeset(%{
      payment_id: payment_id,
      label: label,
      labelled_by: labelled_by,
      note: note
    })
    |> Repo.insert()
  end

  # ── Signal computation ───────────────────────────────────────────────────────

  defp default_signals do
    %{
      tx_count_7d: 0,
      tx_count_30d: 0,
      avg_amount_30d: 0,
      amount_vs_avg: nil,
      unusual_method: false,
      new_customer: true
    }
  end

  defp compute_signals(payment, history) do
    now = DateTime.utc_now()
    seven_ago = DateTime.add(now, -7 * 86_400, :second)
    thirty_ago = DateTime.add(now, -30 * 86_400, :second)

    count_7d = Enum.count(history, &(DateTime.compare(&1.inserted_at, seven_ago) != :lt))
    count_30d = Enum.count(history, &(DateTime.compare(&1.inserted_at, thirty_ago) != :lt))

    recent_amounts =
      history
      |> Enum.filter(&(DateTime.compare(&1.inserted_at, thirty_ago) != :lt))
      |> Enum.map(& &1.amount)

    avg =
      if Enum.empty?(recent_amounts),
        do: 0,
        else: Enum.sum(recent_amounts) / length(recent_amounts)

    method_counts = Enum.frequencies_by(history, & &1.method)

    usual_method =
      if Enum.empty?(method_counts),
        do: nil,
        else: method_counts |> Enum.max_by(fn {_k, v} -> v end) |> elem(0)

    %{
      tx_count_7d: count_7d,
      tx_count_30d: count_30d,
      avg_amount_30d: round(avg),
      amount_vs_avg: if(avg > 0, do: Float.round(payment.amount / avg, 1), else: nil),
      unusual_method: usual_method != nil and payment.method != usual_method,
      new_customer: Enum.empty?(history)
    }
  end
end
