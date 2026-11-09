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
        %RiskLabel{}
        |> RiskLabel.changeset(%{
          payment_id: payment.id,
          label: label,
          labelled_by: dispositioned_by,
          note: note
        })
        |> Repo.insert()
        |> tap(fn
          {:ok, rl} ->
            Logger.info("risk.case_disposed",
              payment_id: payment_id,
              label: rl.label,
              dispositioned_by: dispositioned_by
            )

          _ ->
            :ok
        end)
    end
  end

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
  Fetch a single flagged payment with its risk labels.
  Returns {:ok, {payment, labels}} | {:error, :not_found}.
  """
  def get_case(payment_id) do
    case Repo.get(Payment, payment_id) do
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

        {:ok, {payment, labels}}
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
end
