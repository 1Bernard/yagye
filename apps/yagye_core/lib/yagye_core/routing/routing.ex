defmodule YagyeCore.Routing do
  @moduledoc false

  import Ecto.Query

  require Logger

  alias Ecto.Multi
  alias YagyeCore.Repo

  alias YagyeCore.Providers.Schemas.Provider

  alias YagyeCore.Routing.CircuitBreaker

  alias YagyeCore.Routing.Schemas.{
    RoutingConfiguration,
    RoutingRule,
    RoutingRuleAction,
    RoutingRuleCondition
  }

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

  # Routing rules are never hard-deleted — they are deactivated.
  # Hard deletion would destroy the audit trail of which rule routed which payment.
  def deactivate_rule(%RoutingRule{} = rule) do
    rule
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
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

  # Evaluates active rules for a merchant (merchant-scope first, then platform-scope).
  # Returns {:ok, {provider_id, rule_id}} for the first matching rule so the caller
  # can record which rule drove the routing decision on the payment attempt.
  #
  # Payment attrs expected: %{method: _, currency: _, amount: _, amount_min: _, amount_max: _}
  # Extend as more condition fields become available (risk_score at P20, etc.).
  # Evaluates active routing rules for a merchant.
  # excluded_provider_ids: provider UUIDs already attempted on this payment (for retry fallback).
  def evaluate(merchant_id, mode, payment_attrs, excluded_provider_ids \\ []) do
    {:ok, rules} = list_rules(mode: mode, merchant_id: merchant_id)

    # Merge manually-excluded providers (already-tried retries) with providers whose
    # circuit breakers are open. Half-open providers are intentionally kept — the next
    # payment to them acts as the probe that decides whether to close or re-open.
    open_circuit_ids = CircuitBreaker.open_provider_ids()
    all_excluded = Enum.uniq(excluded_provider_ids ++ open_circuit_ids)

    ordered =
      Enum.sort_by(rules, fn r -> {if(r.scope == "merchant", do: 0, else: 1), r.priority} end)

    matching_rule =
      Enum.find(ordered, fn rule ->
        rule_matches?(rule, payment_attrs) and
          not rule_excluded?(rule, all_excluded)
      end)

    case matching_rule do
      nil ->
        {:error, :no_matching_rule}

      %{split_group_id: g} when not is_nil(g) ->
        evaluate_split_group(ordered, g, payment_attrs, all_excluded)

      rule ->
        resolve_rule_action(rule, all_excluded)
    end
  end

  defp evaluate_split_group(ordered, group_id, payment_attrs, all_excluded) do
    siblings =
      Enum.filter(ordered, fn r ->
        r.split_group_id == group_id and
          rule_matches?(r, payment_attrs) and
          not rule_excluded?(r, all_excluded)
      end)

    case weighted_select_rule(siblings) do
      nil -> {:error, :no_matching_rule}
      selected -> resolve_rule_action(selected, all_excluded)
    end
  end

  defp resolve_rule_action(rule, all_excluded) do
    action =
      rule.actions
      |> Enum.sort_by(& &1.priority)
      |> Enum.find(fn a -> a.provider_id not in all_excluded end)

    if action do
      {:ok, {action.provider_id, rule.id, rule.routing_configuration_id}}
    else
      {:error, :rule_has_no_actions}
    end
  end

  # Weighted random selection across a list of rules carrying a :weight field.
  # Returns nil on empty input; the single element if only one rule exists.
  defp weighted_select_rule([]), do: nil
  defp weighted_select_rule([rule]), do: rule

  defp weighted_select_rule(rules) do
    total = Enum.sum(Enum.map(rules, fn r -> r.weight || 100 end))
    rand = :rand.uniform(total)

    rules
    |> Enum.reduce_while({0, List.last(rules)}, fn rule, {acc, _last} ->
      new_acc = acc + (rule.weight || 100)
      if rand <= new_acc, do: {:halt, {new_acc, rule}}, else: {:cont, {new_acc, rule}}
    end)
    |> elem(1)
  end

  defp rule_excluded?(%RoutingRule{actions: actions}, excluded) when excluded != [] do
    Enum.all?(actions, fn a -> a.provider_id in excluded end)
  end

  defp rule_excluded?(_rule, _excluded), do: false

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

  # ── Routing Configurations ───────────────────────────────────────────────────

  def list_configurations(opts \\ []) do
    scope = Keyword.get(opts, :scope, "platform")
    state = Keyword.get(opts, :state)

    base =
      from(c in RoutingConfiguration,
        where: c.scope == ^scope,
        order_by: [desc: c.inserted_at]
      )

    query = if state, do: where(base, [c], c.state == ^state), else: base
    {:ok, Repo.all(query)}
  end

  def get_configuration(id) do
    case Repo.get(RoutingConfiguration, id) do
      nil -> {:error, :not_found}
      config -> {:ok, config}
    end
  end

  def create_configuration(attrs) do
    %RoutingConfiguration{}
    |> RoutingConfiguration.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_configuration(%RoutingConfiguration{} = config, attrs) do
    config
    |> RoutingConfiguration.update_changeset(attrs)
    |> Repo.update()
  end

  # Publishes a routing configuration and compiles its graph into RoutingRule rows.
  #
  # The Drawflow graph (graph_payload) is a UX abstraction. On publish we "compile"
  # it into normalized routing_rules + conditions + actions rows. This separates
  # the configure phase (ops uses the visual editor) from the execute phase
  # (PaymentDispatchWorker evaluates rules via Routing.evaluate/3).
  #
  # The previous published configuration for the same scope/merchant is archived
  # so its rules are deactivated. Only one configuration is active at a time.
  def publish_configuration(%RoutingConfiguration{} = config) do
    Multi.new()
    |> Multi.run(:archive_previous, fn _repo, _changes ->
      archive_previous_published(config)
    end)
    |> Multi.run(:deactivate_previous_rules, fn _repo, _changes ->
      deactivate_compiled_rules_except(config.id)
    end)
    |> Multi.run(:compile, fn _repo, _changes ->
      compile_graph(config)
    end)
    |> Multi.run(:published, fn _repo, %{compile: compiled_summary} ->
      config
      |> RoutingConfiguration.publish_changeset()
      |> Ecto.Changeset.put_change(:compiled_rules, compiled_summary)
      |> Repo.update()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{published: config}} -> {:ok, config}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  def archive_configuration(%RoutingConfiguration{} = config) do
    config
    |> RoutingConfiguration.archive_changeset()
    |> Repo.update()
  end

  # ── Graph Compiler ───────────────────────────────────────────────────────────
  #
  # Walks the Drawflow graph and produces RoutingRule + condition + action rows.
  #
  # Node vocabulary:
  #   ProviderNode  — terminal; selects a specific provider
  #   ConditionNode — branches: output_1 = condition matches, output_2 = does not match
  #   FallbackNode  — terminal; like ProviderNode but marks this as the retry target
  #   SplitNode     — branches: output_1 = pct_a% of traffic, output_2 = pct_b%
  #                   (percentage split is informational only — both branches compile;
  #                    true weighted split requires runtime support, planned for later)
  #
  # Each root-to-terminal path becomes one RoutingRule. Conditions accumulated along
  # the path become RoutingRuleConditions (AND semantics). The terminal node's
  # provider_code is looked up to get provider_id for the RoutingRuleAction.
  #
  # Priority is assigned by path discovery order — earlier paths (more specific,
  # appearing higher in a DFS walk) get lower priority numbers (checked first).

  # RoutingConfiguration has no mode field — compiled rules always target "live".
  # Routing configurations are ops-managed production routing logic. Simulation mode
  # always routes to the simulator (no rules needed); sandbox mirrors live for testing.
  @default_compile_mode "live"

  defp compile_graph(%RoutingConfiguration{
         graph_payload: payload,
         id: config_id,
         scope: scope,
         merchant_id: merchant_id
       }) do
    nodes = Map.new(payload["nodes"] || [], fn n -> {n["id"], n} end)
    edges_by_source = build_edges_index(payload["edges"] || [])

    # Nodes with no incoming edges are graph entry points.
    all_targets = MapSet.new(payload["edges"] || [], & &1["target"])
    roots = Enum.filter(payload["nodes"] || [], fn n -> n["id"] not in all_targets end)

    mode = Map.get(payload, "mode") || @default_compile_mode

    paths =
      Enum.flat_map(roots, fn root ->
        walk_paths(root, nodes, edges_by_source, [])
      end)

    if Enum.empty?(paths) do
      {:ok, %{"rule_count" => 0, "compiled_at" => DateTime.to_iso8601(DateTime.utc_now())}}
    else
      provider_cache = build_provider_cache(paths)
      errors = compile_paths(paths, provider_cache, config_id, scope, merchant_id, mode)

      if errors == [] do
        summary = %{
          "rule_count" => length(paths),
          "compiled_at" => DateTime.to_iso8601(DateTime.utc_now()),
          "paths" =>
            Enum.map(paths, fn {conditions, terminal, _split_meta} ->
              %{
                "provider" => terminal["data"]["provider_code"],
                "condition_count" => length(conditions)
              }
            end)
        }

        {:ok, summary}
      else
        {:error, {:compilation_failed, errors}}
      end
    end
  end

  defp build_edges_index(edges) do
    Enum.group_by(edges, & &1["source"])
  end

  # DFS walk from a node, accumulating conditions.
  # Returns a list of {conditions, terminal_node, split_meta} triples — one per complete path.
  # split_meta is %{} for non-split paths, or %{split_group_id: uuid, weight: int} for split paths.
  defp walk_paths(node, nodes, edges_by_source, conds) do
    case node["type"] do
      type when type in ["ProviderNode", "FallbackNode"] ->
        [{conds, node, %{}}]

      "ConditionNode" ->
        walk_condition_node(node, nodes, edges_by_source, conds)

      "SplitNode" ->
        walk_split_node(node, nodes, edges_by_source, conds)

      _ ->
        []
    end
  end

  defp walk_condition_node(node, nodes, edges_by_source, conds) do
    outgoing = Map.get(edges_by_source, node["id"], [])
    match_targets = for e <- outgoing, e["sourceHandle"] == "output_1", do: e["target"]
    no_match_targets = for e <- outgoing, e["sourceHandle"] == "output_2", do: e["target"]

    match_cond = node_condition(node, :match)
    no_match_cond = node_condition(node, :no_match)

    match_paths =
      Enum.flat_map(match_targets, fn tid ->
        case Map.get(nodes, tid) do
          nil -> []
          target -> walk_paths(target, nodes, edges_by_source, conds ++ [match_cond])
        end
      end)

    no_match_paths =
      Enum.flat_map(no_match_targets, fn tid ->
        case Map.get(nodes, tid) do
          nil -> []
          target -> walk_paths(target, nodes, edges_by_source, conds ++ [no_match_cond])
        end
      end)

    match_paths ++ no_match_paths
  end

  # Compiles both SplitNode branches with a shared split_group_id so evaluate/4
  # can collect siblings and do weighted random selection at runtime.
  # pct_a/pct_b from the node data are stored as integer weights (ratio-based, not percent).
  defp walk_split_node(node, nodes, edges_by_source, conds) do
    outgoing = Map.get(edges_by_source, node["id"], [])
    group_id = Uniq.UUID.uuid7()

    pct_a = round(get_in(node, ["data", "pct_a"]) || 50)
    pct_b = round(get_in(node, ["data", "pct_b"]) || 50)

    branch_a = for e <- outgoing, e["sourceHandle"] == "output_1", do: {e["target"], pct_a}
    branch_b = for e <- outgoing, e["sourceHandle"] == "output_2", do: {e["target"], pct_b}

    Enum.flat_map(branch_a ++ branch_b, fn {tid, weight} ->
      case Map.get(nodes, tid) do
        nil ->
          []

        target ->
          walk_paths(target, nodes, edges_by_source, conds)
          |> Enum.map(&tag_split_meta(&1, group_id, weight))
      end
    end)
  end

  # Attaches split group metadata to a compiled path tuple.
  # put_new ensures an inner SplitNode's group_id is not overwritten by an outer one.
  defp tag_split_meta({c, t, existing_meta}, group_id, weight) do
    split_meta =
      existing_meta
      |> Map.put_new(:split_group_id, group_id)
      |> Map.put_new(:weight, weight)

    {c, t, split_meta}
  end

  defp node_condition(%{"data" => data}, direction) do
    op = data["operator"] || "eq"

    actual_op =
      case direction do
        :match -> op
        :no_match -> negate_operator(op)
      end

    %{field: data["field"], operator: actual_op, value: wrap_condition_value(op, data["value"])}
  end

  defp negate_operator("eq"), do: "neq"
  defp negate_operator("neq"), do: "eq"
  defp negate_operator("gt"), do: "lte"
  defp negate_operator("gte"), do: "lt"
  defp negate_operator("lt"), do: "gte"
  defp negate_operator("lte"), do: "gt"
  defp negate_operator("in"), do: "not_in"
  defp negate_operator("not_in"), do: "in"
  defp negate_operator(op), do: op

  # The DB and evaluator store condition values as %{"v" => value}.
  # The Drawflow graph stores plain scalars. Wrap them here.
  defp wrap_condition_value(op, value) when op in ["in", "not_in"] do
    list =
      cond do
        is_list(value) -> value
        is_binary(value) -> String.split(value, ",") |> Enum.map(&String.trim/1)
        true -> [value]
      end

    %{"v" => list}
  end

  defp wrap_condition_value(_op, value), do: %{"v" => value}

  defp build_provider_cache(paths) do
    codes =
      paths
      |> Enum.map(fn {_conds, terminal, _meta} -> terminal["data"]["provider_code"] end)
      |> Enum.uniq()
      |> Enum.reject(&is_nil/1)

    from(p in Provider, where: p.code in ^codes, select: {p.code, p.id})
    |> Repo.all()
    |> Map.new()
  end

  defp compile_paths(paths, provider_cache, config_id, scope, merchant_id, mode) do
    ctx = %{config_id: config_id, scope: scope, merchant_id: merchant_id, mode: mode}

    paths
    |> Enum.with_index()
    |> Enum.flat_map(fn {{conditions, terminal, split_meta}, priority} ->
      compile_path(conditions, terminal, provider_cache, ctx, priority, split_meta)
    end)
  end

  defp compile_path(conditions, terminal, provider_cache, ctx, priority, split_meta) do
    provider_code = terminal["data"]["provider_code"]
    provider_id = Map.get(provider_cache, provider_code)

    if is_nil(provider_id) do
      Logger.warning("[routing] compile skipping unknown provider_code=#{provider_code}")
      [{:error, "unknown provider: #{provider_code}"}]
    else
      case insert_compiled_rule(conditions, provider_id, ctx, priority, split_meta) do
        {:ok, _} -> []
        {:error, reason} -> [{:error, reason}]
      end
    end
  end

  defp insert_compiled_rule(conditions, provider_id, ctx, priority, split_meta) do
    rule_attrs = %{
      scope: ctx.scope,
      merchant_id: ctx.merchant_id,
      routing_configuration_id: ctx.config_id,
      mode: ctx.mode,
      name: "compiled_#{priority}",
      priority: priority,
      active: true,
      split_group_id: Map.get(split_meta, :split_group_id),
      weight: Map.get(split_meta, :weight, 100)
    }

    Multi.new()
    |> Multi.insert(:rule, RoutingRule.changeset(%RoutingRule{}, rule_attrs))
    |> Multi.run(:conditions, fn _repo, %{rule: rule} ->
      insert_conditions(rule.id, conditions)
    end)
    |> Multi.insert(:action, fn %{rule: rule} ->
      RoutingRuleAction.changeset(%RoutingRuleAction{}, %{
        rule_id: rule.id,
        provider_id: provider_id,
        priority: 0
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{rule: rule}} -> {:ok, rule}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  defp insert_conditions(_rule_id, []), do: {:ok, []}

  defp insert_conditions(rule_id, conditions) do
    results =
      conditions
      |> Enum.with_index()
      |> Enum.map(fn {cond_attrs, pos} ->
        attrs = Map.merge(cond_attrs, %{rule_id: rule_id, position: pos})

        %RoutingRuleCondition{}
        |> RoutingRuleCondition.changeset(attrs)
        |> Repo.insert()
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))
    if Enum.empty?(errors), do: {:ok, results}, else: hd(errors)
  end

  defp archive_previous_published(%RoutingConfiguration{id: id, scope: scope, merchant_id: mid}) do
    query =
      from(c in RoutingConfiguration,
        where: c.state == "published" and c.id != ^id and c.scope == ^scope
      )

    query =
      if mid do
        where(query, [c], c.merchant_id == ^mid)
      else
        where(query, [c], is_nil(c.merchant_id))
      end

    {_count, _} =
      Repo.update_all(query,
        set: [state: "archived", archived_at: DateTime.utc_now()]
      )

    {:ok, :archived}
  end

  defp deactivate_compiled_rules_except(config_id) do
    # Deactivate all compiled rules that belong to OTHER configurations.
    # Rules with routing_configuration_id IS NULL are ops-managed and untouched.
    {_count, _} =
      from(r in RoutingRule,
        where: not is_nil(r.routing_configuration_id) and r.routing_configuration_id != ^config_id
      )
      |> Repo.update_all(set: [active: false])

    {:ok, :deactivated}
  end
end
