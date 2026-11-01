defmodule YagyeCore.Splits do
  @moduledoc false

  import Ecto.Query

  alias YagyeCore.Repo
  alias YagyeCore.Splits.Schemas.{SplitRecord, SplitRule, SplitRuleLeg}

  # ── Split Rules ──────────────────────────────────────────────────────────────

  @doc """
  Creates a split rule with the given legs (at least one required).
  Validates that percentage legs sum to exactly 100 * 100 bps (10_000) or that
  flat legs are positive amounts.
  """
  def create_rule(attrs, legs_attrs) when is_list(legs_attrs) and legs_attrs != [] do
    with :ok <- validate_legs(legs_attrs) do
      Repo.transaction(fn -> do_create_rule(attrs, legs_attrs) end)
      |> case do
        {:ok, rule} -> {:ok, rule}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def create_rule(_attrs, _legs_attrs), do: {:error, :legs_required}

  @doc """
  Returns a split rule by public_id, preloading legs.
  """
  def get_rule(public_id) do
    case Repo.get_by(SplitRule, public_id: public_id) |> preload_legs() do
      nil -> {:error, :not_found}
      rule -> {:ok, rule}
    end
  end

  @doc """
  Lists active split rules for a merchant.
  """
  def list_rules(merchant_id) do
    SplitRule
    |> where([r], r.merchant_id == ^merchant_id and r.active == true)
    |> order_by([r], [r.inserted_at])
    |> Repo.all()
  end

  @doc """
  Deactivates a split rule.
  """
  def deactivate_rule(public_id) do
    with {:ok, rule} <- get_rule(public_id) do
      rule
      |> Ecto.Changeset.change(active: false)
      |> Repo.update()
    end
  end

  # ── Split Records ────────────────────────────────────────────────────────────

  @doc """
  Creates split records for a payment based on its associated split rule.
  Each leg of the rule generates one split_record.
  Called by SplitDistributorWorker after payment.succeeded.
  """
  def create_records_for_payment(payment, %SplitRule{} = rule) do
    legs = Repo.preload(rule, :legs).legs
    Repo.transaction(fn -> do_create_records(payment, legs) end)
  end

  @doc """
  Returns all split records for a payment.
  """
  def list_records_for_payment(payment_id) do
    SplitRecord
    |> where([r], r.payment_id == ^payment_id)
    |> order_by([r], r.inserted_at)
    |> Repo.all()
  end

  @doc """
  Transitions a split record to settled and stamps settled_at.
  """
  def mark_settled(split_record_id) do
    case Repo.get(SplitRecord, split_record_id) do
      nil ->
        {:error, :not_found}

      record ->
        record
        |> SplitRecord.transition_changeset("settled")
        |> Ecto.Changeset.put_change(:settled_at, DateTime.utc_now())
        |> Repo.update()
    end
  end

  @doc """
  Resolves the split rule for a payment if split_rule_id is present.
  Returns {:ok, rule} | {:ok, :no_split} | {:error, reason}.
  """
  def split_rule_for(payment) do
    case payment.split_rule_id do
      nil ->
        {:ok, :no_split}

      rule_id ->
        case Repo.get(SplitRule, rule_id) do
          nil -> {:error, :split_rule_not_found}
          rule -> {:ok, rule}
        end
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp do_create_rule(attrs, legs_attrs) do
    with {:ok, rule} <- Repo.insert(SplitRule.changeset(%SplitRule{}, attrs)),
         {:ok, _} <- insert_legs(rule, legs_attrs) do
      rule
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp do_create_records(payment, legs) do
    legs
    |> Enum.reduce_while([], &insert_leg_record(payment, &1, &2))
    |> case do
      {:error, reason} -> Repo.rollback(reason)
      records -> Enum.reverse(records)
    end
  end

  defp insert_leg_record(payment, leg, acc) do
    amount = compute_leg_amount(leg, payment.amount)

    case Repo.insert(
           SplitRecord.changeset(%SplitRecord{}, %{
             payment_id: payment.id,
             split_rule_id: leg.split_rule_id,
             split_rule_leg_id: leg.id,
             merchant_id: leg.merchant_id,
             amount: amount,
             currency: payment.currency,
             mode: payment.mode
           })
         ) do
      {:ok, record} -> {:cont, [record | acc]}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp insert_legs(rule, legs_attrs) do
    results =
      Enum.reduce_while(legs_attrs, [], fn attrs, acc ->
        merged = Map.merge(attrs, %{split_rule_id: rule.id, merchant_id: rule.merchant_id})

        case Repo.insert(SplitRuleLeg.changeset(%SplitRuleLeg{}, merged)) do
          {:ok, leg} -> {:cont, [leg | acc]}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case results do
      {:error, reason} -> {:error, reason}
      legs -> {:ok, Enum.reverse(legs)}
    end
  end

  defp validate_legs(legs_attrs) do
    types = Enum.map(legs_attrs, &(&1[:split_type] || &1["split_type"]))

    if Enum.all?(types, &(&1 == "percentage")) do
      total = Enum.sum(Enum.map(legs_attrs, &(&1[:value] || &1["value"] || 0)))
      if total == 10_000, do: :ok, else: {:error, :legs_must_sum_to_100_percent}
    else
      :ok
    end
  end

  defp compute_leg_amount(%SplitRuleLeg{split_type: "percentage", value: bps}, total) do
    div(total * bps, 10_000)
  end

  defp compute_leg_amount(%SplitRuleLeg{split_type: "flat", value: amount}, _total) do
    amount
  end

  defp preload_legs(nil), do: nil
  defp preload_legs(rule), do: Repo.preload(rule, :legs)
end
