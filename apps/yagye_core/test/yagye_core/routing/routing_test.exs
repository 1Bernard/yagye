defmodule YagyeCore.Routing.RoutingTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.{Fixtures, Routing}

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
      assert {:ok, provider_id} =
               Routing.evaluate(nil, "simulation", %{method: "mobile_money"})

      assert provider_id == provider.id
    end

    test "returns :no_matching_rule when no rule matches" do
      assert {:error, :no_matching_rule} =
               Routing.evaluate(nil, "simulation", %{method: "card"})
    end
  end
end
