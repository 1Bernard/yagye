defmodule YagyeCore.Routing.RoutingTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.{Fixtures, Repo, Routing}
  alias YagyeCore.Routing.Schemas.RoutingRule

  # ── create_rule/1 ─────────────────────────────────────────────────────────

  describe "create_rule/1" do
    test "creates a platform-scope rule" do
      assert {:ok, rule} =
               Routing.create_rule(%{
                 scope: "platform",
                 mode: "simulation",
                 name: "Default MoMo Rule",
                 priority: 0
               })

      assert rule.scope == "platform"
      assert rule.merchant_id == nil
      assert rule.active == true
    end

    test "creates a merchant-scope rule" do
      merchant = Fixtures.merchant_fixture()

      assert {:ok, rule} =
               Routing.create_rule(%{
                 scope: "merchant",
                 merchant_id: merchant.id,
                 mode: "simulation",
                 name: "Merchant Override",
                 priority: 0
               })

      assert rule.merchant_id == merchant.id
    end

    test "rejects platform scope with a merchant_id" do
      merchant = Fixtures.merchant_fixture()

      assert {:error, changeset} =
               Routing.create_rule(%{
                 scope: "platform",
                 merchant_id: merchant.id,
                 mode: "simulation",
                 name: "Bad Rule",
                 priority: 0
               })

      assert "must be nil for platform-scope rules" in errors_on(changeset).merchant_id
    end

    test "rejects merchant scope without a merchant_id" do
      assert {:error, changeset} =
               Routing.create_rule(%{
                 scope: "merchant",
                 mode: "simulation",
                 name: "Bad Rule",
                 priority: 0
               })

      assert "required for merchant-scope rules" in errors_on(changeset).merchant_id
    end

    test "rejects invalid scope" do
      assert {:error, changeset} =
               Routing.create_rule(%{
                 scope: "unknown",
                 mode: "simulation",
                 name: "x",
                 priority: 0
               })

      assert "is invalid" in errors_on(changeset).scope
    end

    test "rejects invalid mode" do
      assert {:error, changeset} =
               Routing.create_rule(%{scope: "platform", mode: "staging", name: "x", priority: 0})

      assert "is invalid" in errors_on(changeset).mode
    end

    test "enforces unique (mode, priority) for platform-scope rules" do
      attrs = %{scope: "platform", mode: "simulation", name: "Rule A", priority: 5}
      assert {:ok, _} = Routing.create_rule(attrs)
      assert {:error, changeset} = Routing.create_rule(Map.put(attrs, :name, "Rule B"))

      assert "a platform rule at this priority already exists for this mode" in errors_on(
               changeset
             ).mode
    end
  end

  # ── add_condition/2 ───────────────────────────────────────────────────────

  describe "add_condition/2" do
    setup do
      {:ok, rule} =
        Routing.create_rule(%{scope: "platform", mode: "simulation", name: "Rule", priority: 0})

      {:ok, rule: rule}
    end

    test "adds a valid condition", %{rule: rule} do
      assert {:ok, cond} =
               Routing.add_condition(rule, %{
                 field: "method",
                 operator: "eq",
                 value: %{"v" => "mobile_money"},
                 position: 0
               })

      assert cond.field == "method"
      assert cond.operator == "eq"
    end

    test "rejects unknown field", %{rule: rule} do
      assert {:error, changeset} =
               Routing.add_condition(rule, %{
                 field: "unknown_field",
                 operator: "eq",
                 value: %{"v" => "x"},
                 position: 0
               })

      assert "is invalid" in errors_on(changeset).field
    end

    test "rejects unknown operator", %{rule: rule} do
      assert {:error, changeset} =
               Routing.add_condition(rule, %{
                 field: "method",
                 operator: "like",
                 value: %{"v" => "x"},
                 position: 0
               })

      assert "is invalid" in errors_on(changeset).operator
    end

    test "enforces unique position within rule", %{rule: rule} do
      attrs = %{field: "currency", operator: "eq", value: %{"v" => "GHS"}, position: 0}
      assert {:ok, _} = Routing.add_condition(rule, attrs)
      assert {:error, changeset} = Routing.add_condition(rule, attrs)
      assert "has already been taken" in errors_on(changeset).rule_id
    end
  end

  # ── add_action/2 ─────────────────────────────────────────────────────────

  describe "add_action/2" do
    setup do
      {:ok, rule} =
        Routing.create_rule(%{scope: "platform", mode: "simulation", name: "Rule", priority: 0})

      provider = Fixtures.provider_fixture()
      {:ok, rule: rule, provider: provider}
    end

    test "adds a valid action", %{rule: rule, provider: provider} do
      assert {:ok, action} =
               Routing.add_action(rule, %{provider_id: provider.id, priority: 0})

      assert action.provider_id == provider.id
      assert action.priority == 0
    end

    test "enforces unique priority within rule", %{rule: rule, provider: provider} do
      assert {:ok, _} = Routing.add_action(rule, %{provider_id: provider.id, priority: 0})

      assert {:error, changeset} =
               Routing.add_action(rule, %{provider_id: provider.id, priority: 0})

      assert "has already been taken" in errors_on(changeset).rule_id
    end
  end

  # ── evaluate/3 ────────────────────────────────────────────────────────────

  describe "evaluate/3" do
    setup do
      provider = Fixtures.provider_fixture()

      {:ok, rule} =
        Routing.create_rule(%{
          scope: "platform",
          mode: "simulation",
          name: "MoMo Rule",
          priority: 0
        })

      {:ok, _} =
        Routing.add_condition(rule, %{
          field: "method",
          operator: "eq",
          value: %{"v" => "mobile_money"},
          position: 0
        })

      {:ok, _} = Routing.add_action(rule, %{provider_id: provider.id, priority: 0})

      {:ok, provider: provider, rule: rule}
    end

    test "returns matching provider", %{provider: provider} do
      assert {:ok, {provider_id, _rule_id, _config_id}} =
               Routing.evaluate(nil, "simulation", %{method: "mobile_money"})

      assert provider_id == provider.id
    end

    test "returns :no_matching_rule when no rule matches" do
      assert {:error, :no_matching_rule} =
               Routing.evaluate(nil, "simulation", %{method: "card"})
    end
  end

  # ── evaluate/4 — operator coverage ───────────────────────────────────────

  describe "evaluate/4 — condition operators" do
    setup do
      provider = Fixtures.provider_fixture()

      {:ok, rule} =
        Routing.create_rule(%{scope: "platform", mode: "simulation", name: "Rule", priority: 0})

      {:ok, provider: provider, rule: rule}
    end

    test "gt matches when value exceeds threshold", %{provider: provider, rule: rule} do
      Routing.add_condition(rule, %{
        field: "amount",
        operator: "gt",
        value: %{"v" => 10_000},
        position: 0
      })

      Routing.add_action(rule, %{provider_id: provider.id, priority: 0})

      assert {:ok, _} = Routing.evaluate(nil, "simulation", %{amount: 15_000})
      assert {:error, :no_matching_rule} = Routing.evaluate(nil, "simulation", %{amount: 5_000})
      assert {:error, :no_matching_rule} = Routing.evaluate(nil, "simulation", %{amount: 10_000})
    end

    test "lte matches when value is at or below threshold", %{provider: provider, rule: rule} do
      Routing.add_condition(rule, %{
        field: "amount",
        operator: "lte",
        value: %{"v" => 50_000},
        position: 0
      })

      Routing.add_action(rule, %{provider_id: provider.id, priority: 0})

      assert {:ok, _} = Routing.evaluate(nil, "simulation", %{amount: 50_000})
      assert {:ok, _} = Routing.evaluate(nil, "simulation", %{amount: 1_000})
      assert {:error, :no_matching_rule} = Routing.evaluate(nil, "simulation", %{amount: 50_001})
    end

    test "in matches when value is in list", %{provider: provider, rule: rule} do
      Routing.add_condition(rule, %{
        field: "currency",
        operator: "in",
        value: %{"v" => ["GHS", "NGN"]},
        position: 0
      })

      Routing.add_action(rule, %{provider_id: provider.id, priority: 0})

      assert {:ok, _} = Routing.evaluate(nil, "simulation", %{currency: "GHS"})
      assert {:ok, _} = Routing.evaluate(nil, "simulation", %{currency: "NGN"})
      assert {:error, :no_matching_rule} = Routing.evaluate(nil, "simulation", %{currency: "USD"})
    end

    test "not_in excludes listed values", %{provider: provider, rule: rule} do
      Routing.add_condition(rule, %{
        field: "currency",
        operator: "not_in",
        value: %{"v" => ["USD", "EUR"]},
        position: 0
      })

      Routing.add_action(rule, %{provider_id: provider.id, priority: 0})

      assert {:ok, _} = Routing.evaluate(nil, "simulation", %{currency: "GHS"})
      assert {:error, :no_matching_rule} = Routing.evaluate(nil, "simulation", %{currency: "USD"})
    end

    test "network eq matches mobile money network", %{provider: provider, rule: rule} do
      Routing.add_condition(rule, %{
        field: "network",
        operator: "eq",
        value: %{"v" => "MTN"},
        position: 0
      })

      Routing.add_action(rule, %{provider_id: provider.id, priority: 0})

      assert {:ok, _} = Routing.evaluate(nil, "simulation", %{network: "MTN"})

      assert {:error, :no_matching_rule} =
               Routing.evaluate(nil, "simulation", %{network: "TELECEL"})

      assert {:error, :no_matching_rule} = Routing.evaluate(nil, "simulation", %{network: nil})
    end

    test "multiple conditions use AND semantics — all must match", %{
      provider: provider,
      rule: rule
    } do
      Routing.add_condition(rule, %{
        field: "method",
        operator: "eq",
        value: %{"v" => "mobile_money"},
        position: 0
      })

      Routing.add_condition(rule, %{
        field: "network",
        operator: "eq",
        value: %{"v" => "MTN"},
        position: 1
      })

      Routing.add_action(rule, %{provider_id: provider.id, priority: 0})

      assert {:ok, _} =
               Routing.evaluate(nil, "simulation", %{method: "mobile_money", network: "MTN"})

      assert {:error, :no_matching_rule} =
               Routing.evaluate(nil, "simulation", %{method: "mobile_money", network: "TELECEL"})

      assert {:error, :no_matching_rule} =
               Routing.evaluate(nil, "simulation", %{method: "card", network: "MTN"})
    end
  end

  # ── evaluate/4 — provider exclusion ──────────────────────────────────────

  describe "evaluate/4 — excluded providers" do
    test "skips a rule when its only action is excluded" do
      provider = Fixtures.provider_fixture()

      {:ok, rule} =
        Routing.create_rule(%{scope: "platform", mode: "simulation", name: "Rule", priority: 0})

      Routing.add_condition(rule, %{
        field: "method",
        operator: "eq",
        value: %{"v" => "mobile_money"},
        position: 0
      })

      Routing.add_action(rule, %{provider_id: provider.id, priority: 0})

      assert {:error, :no_matching_rule} =
               Routing.evaluate(nil, "simulation", %{method: "mobile_money"}, [provider.id])
    end

    test "falls through to next rule when first rule is excluded" do
      primary = Fixtures.provider_fixture()
      secondary = Fixtures.provider_fixture()

      {:ok, rule_a} =
        Routing.create_rule(%{
          scope: "platform",
          mode: "simulation",
          name: "Primary",
          priority: 0
        })

      {:ok, rule_b} =
        Routing.create_rule(%{
          scope: "platform",
          mode: "simulation",
          name: "Secondary",
          priority: 1
        })

      Routing.add_condition(rule_a, %{
        field: "method",
        operator: "eq",
        value: %{"v" => "mobile_money"},
        position: 0
      })

      Routing.add_action(rule_a, %{provider_id: primary.id, priority: 0})

      Routing.add_condition(rule_b, %{
        field: "method",
        operator: "eq",
        value: %{"v" => "mobile_money"},
        position: 0
      })

      Routing.add_action(rule_b, %{provider_id: secondary.id, priority: 0})

      # Without exclusion the primary wins
      assert {:ok, {primary_id, _, _}} =
               Routing.evaluate(nil, "simulation", %{method: "mobile_money"})

      assert primary_id == primary.id

      # Exclude primary — secondary wins
      assert {:ok, {secondary_id, _, _}} =
               Routing.evaluate(nil, "simulation", %{method: "mobile_money"}, [primary.id])

      assert secondary_id == secondary.id
    end
  end

  # ── evaluate/4 — scope precedence ────────────────────────────────────────

  describe "evaluate/4 — merchant-scope precedence" do
    test "merchant-scope rule wins over platform-scope at same priority" do
      platform_provider = Fixtures.provider_fixture()
      merchant_provider = Fixtures.provider_fixture()
      merchant = Fixtures.merchant_fixture()

      {:ok, platform_rule} =
        Routing.create_rule(%{
          scope: "platform",
          mode: "simulation",
          name: "Platform",
          priority: 0
        })

      {:ok, merchant_rule} =
        Routing.create_rule(%{
          scope: "merchant",
          merchant_id: merchant.id,
          mode: "simulation",
          name: "Merchant",
          priority: 0
        })

      for rule <- [platform_rule, merchant_rule] do
        Routing.add_condition(rule, %{
          field: "method",
          operator: "eq",
          value: %{"v" => "mobile_money"},
          position: 0
        })
      end

      Routing.add_action(platform_rule, %{provider_id: platform_provider.id, priority: 0})
      Routing.add_action(merchant_rule, %{provider_id: merchant_provider.id, priority: 0})

      assert {:ok, {selected, _, _}} =
               Routing.evaluate(merchant.id, "simulation", %{method: "mobile_money"})

      assert selected == merchant_provider.id
    end

    test "platform rule applies when no merchant rule matches" do
      platform_provider = Fixtures.provider_fixture()
      merchant = Fixtures.merchant_fixture()

      {:ok, rule} =
        Routing.create_rule(%{
          scope: "platform",
          mode: "simulation",
          name: "Platform",
          priority: 0
        })

      Routing.add_condition(rule, %{
        field: "method",
        operator: "eq",
        value: %{"v" => "mobile_money"},
        position: 0
      })

      Routing.add_action(rule, %{provider_id: platform_provider.id, priority: 0})

      assert {:ok, {selected, _, _}} =
               Routing.evaluate(merchant.id, "simulation", %{method: "mobile_money"})

      assert selected == platform_provider.id
    end
  end

  # ── publish_configuration/1 — graph compiler ─────────────────────────────

  describe "publish_configuration/1" do
    test "single ProviderNode compiles to one active routing rule" do
      provider = Fixtures.provider_fixture()
      {:ok, config} = build_config(single_node_graph(provider.code, "ProviderNode"))

      assert {:ok, published} = Routing.publish_configuration(config)
      assert published.state == "published"
      assert published.compiled_rules["rule_count"] == 1

      {:ok, rules} = Routing.list_rules(mode: "live")
      assert length(rules) == 1
      [rule] = rules
      assert rule.active == true
      assert rule.routing_configuration_id == config.id
      assert length(rule.actions) == 1
      assert hd(rule.actions).provider_id == provider.id
    end

    test "FallbackNode compiles the same as ProviderNode" do
      provider = Fixtures.provider_fixture()
      {:ok, config} = build_config(single_node_graph(provider.code, "FallbackNode"))

      assert {:ok, _} = Routing.publish_configuration(config)
      {:ok, rules} = Routing.list_rules(mode: "live")
      assert length(rules) == 1
    end

    test "ConditionNode creates a match path (eq) and a no-match path (neq)" do
      provider_a = Fixtures.provider_fixture()
      provider_b = Fixtures.provider_fixture()

      {:ok, config} =
        build_config(condition_graph("network", "eq", "MTN", provider_a.code, provider_b.code))

      assert {:ok, _} = Routing.publish_configuration(config)
      {:ok, rules} = Routing.list_rules(mode: "live")
      assert length(rules) == 2

      match_rule = Enum.find(rules, fn r -> Enum.any?(r.conditions, &(&1.operator == "eq")) end)

      no_match_rule =
        Enum.find(rules, fn r -> Enum.any?(r.conditions, &(&1.operator == "neq")) end)

      assert match_rule.actions |> hd() |> Map.get(:provider_id) == provider_a.id
      assert no_match_rule.actions |> hd() |> Map.get(:provider_id) == provider_b.id
    end

    test "SplitNode compiles both branches without adding conditions" do
      provider_a = Fixtures.provider_fixture()
      provider_b = Fixtures.provider_fixture()

      {:ok, config} = build_config(split_graph(provider_a.code, provider_b.code))

      assert {:ok, _} = Routing.publish_configuration(config)
      {:ok, rules} = Routing.list_rules(mode: "live")
      assert length(rules) == 2
      assert Enum.all?(rules, fn r -> r.conditions == [] end)
    end

    test "empty graph publishes with zero rules" do
      {:ok, config} = build_config(%{"nodes" => [], "edges" => [], "schema_version" => 1})

      assert {:ok, published} = Routing.publish_configuration(config)
      assert published.compiled_rules["rule_count"] == 0
      assert published.state == "published"
    end

    test "unknown provider_code returns compilation error" do
      {:ok, config} = build_config(single_node_graph("no_such_provider", "ProviderNode"))

      assert {:error, {:compilation_failed, errors}} = Routing.publish_configuration(config)
      assert length(errors) == 1
    end

    test "publishing archives the previous published config" do
      provider = Fixtures.provider_fixture()
      graph = single_node_graph(provider.code, "ProviderNode")

      {:ok, config1} = build_config(graph)
      assert {:ok, _} = Routing.publish_configuration(config1)

      {:ok, config2} = build_config(graph)
      assert {:ok, _} = Routing.publish_configuration(config2)

      {:ok, config1_reloaded} = Routing.get_configuration(config1.id)
      assert config1_reloaded.state == "archived"
    end

    test "publishing deactivates compiled rules from the previous config" do
      provider = Fixtures.provider_fixture()
      graph = single_node_graph(provider.code, "ProviderNode")

      {:ok, config1} = build_config(graph)
      {:ok, _} = Routing.publish_configuration(config1)

      {:ok, config2} = build_config(graph)
      {:ok, _} = Routing.publish_configuration(config2)

      old_rules =
        from(r in RoutingRule, where: r.routing_configuration_id == ^config1.id)
        |> Repo.all()

      assert Enum.all?(old_rules, fn r -> r.active == false end)
    end

    test "three independent network paths each compile to one explicit-condition rule" do
      mtn = Fixtures.provider_fixture(%{code: "mtn_ind_#{System.unique_integer([:positive])}"})

      telecel =
        Fixtures.provider_fixture(%{code: "tcl_ind_#{System.unique_integer([:positive])}"})

      airteltigo =
        Fixtures.provider_fixture(%{code: "atg_ind_#{System.unique_integer([:positive])}"})

      # Canonical Model-A template: three independent root pairs, one per network.
      # Each ConditionNode is a root (no incoming edge); only the match (output_1)
      # branch is wired — no implicit "else" path.
      graph = %{
        "nodes" => [
          %{
            "id" => "n1",
            "type" => "ConditionNode",
            "position" => %{"x" => 0, "y" => 0},
            "data" => %{"field" => "network", "operator" => "eq", "value" => "MTN"}
          },
          %{
            "id" => "n2",
            "type" => "ProviderNode",
            "position" => %{"x" => 300, "y" => 0},
            "data" => %{"provider_code" => mtn.code}
          },
          %{
            "id" => "n3",
            "type" => "ConditionNode",
            "position" => %{"x" => 0, "y" => 200},
            "data" => %{"field" => "network", "operator" => "eq", "value" => "TELECEL"}
          },
          %{
            "id" => "n4",
            "type" => "ProviderNode",
            "position" => %{"x" => 300, "y" => 200},
            "data" => %{"provider_code" => telecel.code}
          },
          %{
            "id" => "n5",
            "type" => "ConditionNode",
            "position" => %{"x" => 0, "y" => 400},
            "data" => %{"field" => "network", "operator" => "eq", "value" => "AIRTELTIGO"}
          },
          %{
            "id" => "n6",
            "type" => "ProviderNode",
            "position" => %{"x" => 300, "y" => 400},
            "data" => %{"provider_code" => airteltigo.code}
          }
        ],
        "edges" => [
          %{
            "id" => "e1",
            "source" => "n1",
            "target" => "n2",
            "sourceHandle" => "output_1",
            "targetHandle" => "input_1"
          },
          %{
            "id" => "e2",
            "source" => "n3",
            "target" => "n4",
            "sourceHandle" => "output_1",
            "targetHandle" => "input_1"
          },
          %{
            "id" => "e3",
            "source" => "n5",
            "target" => "n6",
            "sourceHandle" => "output_1",
            "targetHandle" => "input_1"
          }
        ],
        "schema_version" => 1
      }

      {:ok, config} = build_config(graph)
      assert {:ok, published} = Routing.publish_configuration(config)
      assert published.compiled_rules["rule_count"] == 3

      {:ok, rules} = Routing.list_rules(mode: "live")
      assert length(rules) == 3

      # Every rule has exactly one condition — an explicit network eq check.
      assert Enum.all?(rules, fn r -> length(r.conditions) == 1 end)

      mtn_rule = Enum.find(rules, fn r -> hd(r.actions).provider_id == mtn.id end)
      assert mtn_rule
      assert hd(mtn_rule.conditions).field == "network"
      assert hd(mtn_rule.conditions).operator == "eq"
      assert get_in(hd(mtn_rule.conditions).value, ["v"]) == "MTN"

      telecel_rule = Enum.find(rules, fn r -> hd(r.actions).provider_id == telecel.id end)
      assert telecel_rule
      assert get_in(hd(telecel_rule.conditions).value, ["v"]) == "TELECEL"

      atg_rule = Enum.find(rules, fn r -> hd(r.actions).provider_id == airteltigo.id end)
      assert atg_rule
      assert get_in(hd(atg_rule.conditions).value, ["v"]) == "AIRTELTIGO"
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp build_config(graph_payload) do
    Routing.create_configuration(%{
      scope: "platform",
      name: "Test config #{System.unique_integer([:positive])}",
      graph_payload: graph_payload
    })
  end

  defp single_node_graph(provider_code, type) do
    %{
      "nodes" => [
        %{
          "id" => "n1",
          "type" => type,
          "position" => %{"x" => 0, "y" => 0},
          "data" => %{"provider_code" => provider_code}
        }
      ],
      "edges" => [],
      "schema_version" => 1
    }
  end

  defp condition_graph(field, operator, value, match_provider_code, no_match_provider_code) do
    %{
      "nodes" => [
        %{
          "id" => "n1",
          "type" => "ConditionNode",
          "position" => %{"x" => 0, "y" => 0},
          "data" => %{"field" => field, "operator" => operator, "value" => value}
        },
        %{
          "id" => "n2",
          "type" => "ProviderNode",
          "position" => %{"x" => 200, "y" => 0},
          "data" => %{"provider_code" => match_provider_code}
        },
        %{
          "id" => "n3",
          "type" => "ProviderNode",
          "position" => %{"x" => 200, "y" => 200},
          "data" => %{"provider_code" => no_match_provider_code}
        }
      ],
      "edges" => [
        %{
          "id" => "e1",
          "source" => "n1",
          "target" => "n2",
          "sourceHandle" => "output_1",
          "targetHandle" => "input_1"
        },
        %{
          "id" => "e2",
          "source" => "n1",
          "target" => "n3",
          "sourceHandle" => "output_2",
          "targetHandle" => "input_1"
        }
      ],
      "schema_version" => 1
    }
  end

  defp split_graph(provider_code_a, provider_code_b) do
    %{
      "nodes" => [
        %{
          "id" => "n1",
          "type" => "SplitNode",
          "position" => %{"x" => 0, "y" => 0},
          "data" => %{"pct_a" => 70, "pct_b" => 30}
        },
        %{
          "id" => "n2",
          "type" => "ProviderNode",
          "position" => %{"x" => 200, "y" => 0},
          "data" => %{"provider_code" => provider_code_a}
        },
        %{
          "id" => "n3",
          "type" => "ProviderNode",
          "position" => %{"x" => 200, "y" => 200},
          "data" => %{"provider_code" => provider_code_b}
        }
      ],
      "edges" => [
        %{
          "id" => "e1",
          "source" => "n1",
          "target" => "n2",
          "sourceHandle" => "output_1",
          "targetHandle" => "input_1"
        },
        %{
          "id" => "e2",
          "source" => "n1",
          "target" => "n3",
          "sourceHandle" => "output_2",
          "targetHandle" => "input_1"
        }
      ],
      "schema_version" => 1
    }
  end
end
