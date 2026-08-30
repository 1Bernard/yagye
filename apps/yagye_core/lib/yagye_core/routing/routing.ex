defmodule YagyeCore.Routing do
  @moduledoc false

  import Ecto.Query

  alias YagyeCore.Repo
  alias YagyeCore.Routing.Schemas.{RoutingRule, RoutingRuleAction, RoutingRuleCondition}

  # ── Public API ───────────────────────────────────────────────────────────────

  def list_rules(opts \\ []) do
    mode = Keyword.get(opts, :mode, "live")
    merchant_id = Keyword.get(opts, :merchant_id)

    base =
      from(r in RoutingRule,
        where: r.mode == ^mode and r.active == true,
        order_by: [asc: r.scope, asc: r.priority],
        preload: [:conditions, :actions]
      )

    query =
      if merchant_id do
        where(base, [r], r.scope == "platform" or r.merchant_id == ^merchant_id)
      else
        where(base, [r], r.scope == "platform")
      end

    {:ok, Repo.all(query)}
  end

  def get_rule(id) do
    case Repo.get(RoutingRule, id) do
      nil -> {:error, :not_found}
      rule -> {:ok, Repo.preload(rule, [:conditions, :actions])}
    end
  end

  def create_rule(attrs) do
    %RoutingRule{}
    |> RoutingRule.changeset(attrs)
    |> Repo.insert()
  end

  def update_rule(%RoutingRule{} = rule, attrs) do
    rule
    |> RoutingRule.changeset(attrs)
    |> Repo.update()
  end

  def delete_rule(%RoutingRule{} = rule) do
    Repo.delete(rule)
  end

  def add_condition(%RoutingRule{} = rule, attrs) do
    %RoutingRuleCondition{}
    |> RoutingRuleCondition.changeset(Map.put(attrs, :rule_id, rule.id))
    |> Repo.insert()
  end

  def add_action(%RoutingRule{} = rule, attrs) do
    %RoutingRuleAction{}
    |> RoutingRuleAction.changeset(Map.put(attrs, :rule_id, rule.id))
    |> Repo.insert()
  end

  # ── Evaluation ───────────────────────────────────────────────────────────────

  # Evaluates active rules for a merchant, merchant-scope first then platform-scope.
  # Returns the first provider_id from the first matching rule's actions (by priority).
  def evaluate(merchant_id, mode, payment_attrs) do
    {:ok, rules} = list_rules(mode: mode, merchant_id: merchant_id)

    ordered =
      Enum.sort_by(rules, fn r -> {if(r.scope == "merchant", do: 0, else: 1), r.priority} end)

    case Enum.find(ordered, &rule_matches?(&1, payment_attrs)) do
      nil ->
        {:error, :no_matching_rule}

      rule ->
        action = rule.actions |> Enum.sort_by(& &1.priority) |> List.first()
        if action, do: {:ok, action.provider_id}, else: {:error, :rule_has_no_actions}
    end
  end

  defp rule_matches?(%RoutingRule{conditions: conditions}, attrs) do
    Enum.all?(conditions, &condition_matches?(&1, attrs))
  end

  defp condition_matches?(%RoutingRuleCondition{field: field, operator: op, value: val}, attrs) do
    actual = Map.get(attrs, String.to_existing_atom(field))
    apply_operator(op, actual, val)
  rescue
    ArgumentError -> false
  end

  defp apply_operator("eq", a, %{"v" => v}), do: to_string(a) == to_string(v)
  defp apply_operator("neq", a, %{"v" => v}), do: to_string(a) != to_string(v)
  defp apply_operator("gt", a, %{"v" => v}) when is_number(a), do: a > v
  defp apply_operator("gte", a, %{"v" => v}) when is_number(a), do: a >= v
  defp apply_operator("lt", a, %{"v" => v}) when is_number(a), do: a < v
  defp apply_operator("lte", a, %{"v" => v}) when is_number(a), do: a <= v

  defp apply_operator("in", a, %{"v" => list}) when is_list(list),
    do: to_string(a) in Enum.map(list, &to_string/1)

  defp apply_operator("not_in", a, %{"v" => list}) when is_list(list),
    do: to_string(a) not in Enum.map(list, &to_string/1)

  defp apply_operator(_, _, _), do: false
end
