defmodule YagyeCore.Settlement.SettlementBatchTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.Providers.Schemas.Provider
  alias YagyeCore.Repo
  alias YagyeCore.Settlement.Schemas.SettlementBatch

  defp batch_attrs(merchant, provider, overrides \\ %{}) do
    now = DateTime.utc_now()

    Map.merge(
      %{
        merchant_id: merchant.id,
        provider_id: provider.id,
        currency: "GHS",
        mode: "simulation",
        period_start: DateTime.add(now, -86_400),
        period_end: now
      },
      overrides
    )
  end

  describe "changeset/2" do
    setup do
      merchant = Fixtures.approved_merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()
      %{merchant: merchant, provider: provider}
    end

    test "valid attrs produce a valid changeset", %{merchant: merchant, provider: provider} do
      cs = SettlementBatch.changeset(%SettlementBatch{}, batch_attrs(merchant, provider))
      assert cs.valid?
    end

    test "requires merchant_id", %{merchant: merchant, provider: provider} do
      cs =
        SettlementBatch.changeset(
          %SettlementBatch{},
          batch_attrs(merchant, provider, %{merchant_id: nil})
        )

      assert "can't be blank" in errors_on(cs).merchant_id
    end

    test "requires provider_id", %{merchant: merchant, provider: provider} do
      cs =
        SettlementBatch.changeset(
          %SettlementBatch{},
          batch_attrs(merchant, provider, %{provider_id: nil})
        )

      assert "can't be blank" in errors_on(cs).provider_id
    end

    test "requires currency", %{merchant: merchant, provider: provider} do
      cs =
        SettlementBatch.changeset(
          %SettlementBatch{},
          batch_attrs(merchant, provider, %{currency: nil})
        )

      assert "can't be blank" in errors_on(cs).currency
    end

    test "rejects currency not exactly 3 chars", %{merchant: merchant, provider: provider} do
      cs =
        SettlementBatch.changeset(
          %SettlementBatch{},
          batch_attrs(merchant, provider, %{currency: "GH"})
        )

      assert errors_on(cs).currency != []
    end

    test "rejects invalid state", %{merchant: merchant, provider: provider} do
      cs =
        SettlementBatch.changeset(
          %SettlementBatch{},
          batch_attrs(merchant, provider, %{state: "unknown"})
        )

      assert "is invalid" in errors_on(cs).state
    end

    test "rejects invalid mode", %{merchant: merchant, provider: provider} do
      cs =
        SettlementBatch.changeset(
          %SettlementBatch{},
          batch_attrs(merchant, provider, %{mode: "staging"})
        )

      assert "is invalid" in errors_on(cs).mode
    end

    test "rejects negative payment_count", %{merchant: merchant, provider: provider} do
      cs =
        SettlementBatch.changeset(
          %SettlementBatch{},
          batch_attrs(merchant, provider, %{payment_count: -1})
        )

      assert errors_on(cs).payment_count != []
    end

    test "rejects negative gross_amount", %{merchant: merchant, provider: provider} do
      cs =
        SettlementBatch.changeset(
          %SettlementBatch{},
          batch_attrs(merchant, provider, %{gross_amount: -100})
        )

      assert errors_on(cs).gross_amount != []
    end
  end

  describe "unique constraint (merchant_id, provider_id, currency, mode, period_start, period_end)" do
    test "two batches for the same period conflict" do
      merchant = Fixtures.approved_merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()
      attrs = batch_attrs(merchant, provider)

      {:ok, _} = Repo.insert(SettlementBatch.changeset(%SettlementBatch{}, attrs))

      {:error, cs} = Repo.insert(SettlementBatch.changeset(%SettlementBatch{}, attrs))

      assert errors_on(cs)[:merchant_id] != nil or errors_on(cs)[:provider_id] != nil
    end

    test "same period but different provider is allowed" do
      merchant = Fixtures.approved_merchant_fixture()
      provider_a = Fixtures.simulator_provider_fixture()

      provider_b =
        Repo.insert!(
          %Provider{}
          |> Provider.changeset(%{
            code: "other_provider_#{System.unique_integer([:positive])}",
            display_name: "Other Provider",
            adapter_module: "YagyeCore.Payments.Adapters.SimulatorAdapter",
            active: true
          })
        )

      now = DateTime.utc_now()
      period = %{period_start: DateTime.add(now, -86_400), period_end: now}

      assert {:ok, _} =
               Repo.insert(
                 SettlementBatch.changeset(
                   %SettlementBatch{},
                   batch_attrs(merchant, provider_a, period)
                 )
               )

      assert {:ok, _} =
               Repo.insert(
                 SettlementBatch.changeset(
                   %SettlementBatch{},
                   batch_attrs(merchant, provider_b, period)
                 )
               )
    end
  end

  describe "transition_changeset/2" do
    test "transitions to any valid state" do
      for state <- SettlementBatch.valid_states() do
        batch = %SettlementBatch{state: "pending"}
        cs = SettlementBatch.transition_changeset(batch, state)
        assert Ecto.Changeset.get_field(cs, :state) == state
      end
    end
  end
end
