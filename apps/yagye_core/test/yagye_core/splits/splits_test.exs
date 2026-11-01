defmodule YagyeCore.SplitsTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Repo
  alias YagyeCore.Splits
  alias YagyeCore.Splits.Schemas.SplitRecord

  # ── Fixtures ─────────────────────────────────────────────────────────────────

  defp rule_attrs(merchant) do
    %{merchant_id: merchant.id, name: "50/50 Split", mode: "simulation"}
  end

  defp percentage_legs do
    [
      %{label: "Primary", split_type: "percentage", value: 5_000},
      %{label: "Secondary", split_type: "percentage", value: 5_000}
    ]
  end

  defp flat_legs do
    [
      %{label: "Flat leg 1", split_type: "flat", value: 200},
      %{label: "Flat leg 2", split_type: "flat", value: 300}
    ]
  end

  defp insert_rule(merchant, legs \\ nil) do
    legs = legs || percentage_legs()
    {:ok, rule} = Splits.create_rule(rule_attrs(merchant), legs)
    rule
  end

  defp insert_payment_with_rule(merchant, rule) do
    payment = Fixtures.payment_fixture(merchant, %{split_rule_id: rule.id})
    {:ok, payment} = payment |> Payment.transition_changeset("authorised") |> Repo.update()
    {:ok, payment} = payment |> Payment.transition_changeset("succeeded") |> Repo.update()
    payment
  end

  # ── create_rule/2 ────────────────────────────────────────────────────────────

  describe "create_rule/2" do
    test "creates a split rule with percentage legs" do
      merchant = Fixtures.merchant_fixture()

      assert {:ok, rule} = Splits.create_rule(rule_attrs(merchant), percentage_legs())

      assert rule.public_id =~ "srl_"
      assert rule.merchant_id == merchant.id
      assert rule.active == true
    end

    test "creates a split rule with flat legs" do
      merchant = Fixtures.merchant_fixture()

      assert {:ok, rule} = Splits.create_rule(rule_attrs(merchant), flat_legs())

      assert rule.public_id =~ "srl_"
    end

    test "rejects percentage legs that do not sum to 100%" do
      merchant = Fixtures.merchant_fixture()
      bad_legs = [%{label: "A", split_type: "percentage", value: 3_000}]

      assert {:error, :legs_must_sum_to_100_percent} =
               Splits.create_rule(rule_attrs(merchant), bad_legs)
    end

    test "rejects empty legs list" do
      merchant = Fixtures.merchant_fixture()

      assert {:error, :legs_required} = Splits.create_rule(rule_attrs(merchant), [])
    end
  end

  # ── get_rule/1 ───────────────────────────────────────────────────────────────

  describe "get_rule/1" do
    test "returns rule with preloaded legs" do
      merchant = Fixtures.merchant_fixture()
      rule = insert_rule(merchant)

      assert {:ok, fetched} = Splits.get_rule(rule.public_id)

      assert fetched.id == rule.id
      assert length(fetched.legs) == 2
    end

    test "returns not_found for unknown public_id" do
      assert {:error, :not_found} = Splits.get_rule("srl_does_not_exist")
    end
  end

  # ── list_rules/1 ─────────────────────────────────────────────────────────────

  describe "list_rules/1" do
    test "returns active rules for the merchant" do
      merchant = Fixtures.merchant_fixture()
      _rule1 = insert_rule(merchant)
      _rule2 = insert_rule(merchant)

      rules = Splits.list_rules(merchant.id)

      assert length(rules) == 2
    end

    test "excludes deactivated rules" do
      merchant = Fixtures.merchant_fixture()
      rule = insert_rule(merchant)

      {:ok, _} = Splits.deactivate_rule(rule.public_id)

      assert Splits.list_rules(merchant.id) == []
    end
  end

  # ── deactivate_rule/1 ────────────────────────────────────────────────────────

  describe "deactivate_rule/1" do
    test "sets active to false" do
      merchant = Fixtures.merchant_fixture()
      rule = insert_rule(merchant)

      assert {:ok, updated} = Splits.deactivate_rule(rule.public_id)

      assert updated.active == false
    end

    test "returns not_found for unknown rule" do
      assert {:error, :not_found} = Splits.deactivate_rule("srl_unknown")
    end
  end

  # ── create_records_for_payment/2 ─────────────────────────────────────────────

  describe "create_records_for_payment/2" do
    test "creates one split record per leg" do
      merchant = Fixtures.merchant_fixture()
      rule = insert_rule(merchant)
      payment = insert_payment_with_rule(merchant, rule)

      assert {:ok, records} = Splits.create_records_for_payment(payment, rule)

      assert length(records) == 2
      assert Enum.all?(records, &(&1.state == "pending"))
      assert Enum.all?(records, &(&1.payment_id == payment.id))
    end

    test "computes percentage amounts correctly" do
      merchant = Fixtures.merchant_fixture()

      rule =
        insert_rule(merchant, [
          %{label: "70%", split_type: "percentage", value: 7_000},
          %{label: "30%", split_type: "percentage", value: 3_000}
        ])

      payment = insert_payment_with_rule(merchant, rule)

      assert {:ok, records} = Splits.create_records_for_payment(payment, rule)

      amounts = Enum.map(records, & &1.amount) |> Enum.sort()
      gross = payment.amount
      assert Enum.sort(amounts) == [div(gross * 3_000, 10_000), div(gross * 7_000, 10_000)]
    end

    test "flat legs use fixed amounts" do
      merchant = Fixtures.merchant_fixture()
      rule = insert_rule(merchant, flat_legs())
      payment = insert_payment_with_rule(merchant, rule)

      assert {:ok, records} = Splits.create_records_for_payment(payment, rule)

      amounts = records |> Enum.map(& &1.amount) |> Enum.sort()
      assert amounts == [200, 300]
    end
  end

  # ── list_records_for_payment/1 ───────────────────────────────────────────────

  describe "list_records_for_payment/1" do
    test "returns all records for the payment" do
      merchant = Fixtures.merchant_fixture()
      rule = insert_rule(merchant)
      payment = insert_payment_with_rule(merchant, rule)

      {:ok, _} = Splits.create_records_for_payment(payment, rule)

      records = Splits.list_records_for_payment(payment.id)

      assert length(records) == 2
    end

    test "returns empty list when no records exist" do
      merchant = Fixtures.merchant_fixture()
      payment = Fixtures.payment_fixture(merchant)

      assert Splits.list_records_for_payment(payment.id) == []
    end
  end

  # ── mark_settled/1 ───────────────────────────────────────────────────────────

  describe "mark_settled/1" do
    test "transitions split record to settled" do
      merchant = Fixtures.merchant_fixture()
      rule = insert_rule(merchant)
      payment = insert_payment_with_rule(merchant, rule)

      {:ok, [record | _]} = Splits.create_records_for_payment(payment, rule)

      assert {:ok, settled} = Splits.mark_settled(record.id)

      assert settled.state == "settled"
      assert settled.settled_at != nil
    end

    test "returns not_found for unknown id" do
      assert {:error, :not_found} = Splits.mark_settled(Uniq.UUID.uuid7())
    end
  end

  # ── split_rule_for/1 ─────────────────────────────────────────────────────────

  describe "split_rule_for/1" do
    test "returns the split rule when payment has split_rule_id" do
      merchant = Fixtures.merchant_fixture()
      rule = insert_rule(merchant)
      payment = insert_payment_with_rule(merchant, rule)

      assert {:ok, fetched_rule} = Splits.split_rule_for(payment)

      assert fetched_rule.id == rule.id
    end

    test "returns :no_split when payment has no split_rule_id" do
      merchant = Fixtures.merchant_fixture()
      payment = Fixtures.payment_fixture(merchant)

      assert {:ok, :no_split} = Splits.split_rule_for(payment)
    end
  end

  # ── SplitRecord schema ───────────────────────────────────────────────────────

  describe "SplitRecord.transition_changeset/2" do
    test "transitions pending → settled" do
      merchant = Fixtures.merchant_fixture()
      rule = insert_rule(merchant)
      payment = insert_payment_with_rule(merchant, rule)

      {:ok, [record | _]} = Splits.create_records_for_payment(payment, rule)

      cs = SplitRecord.transition_changeset(record, "settled")

      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :state) == "settled"
    end
  end
end
