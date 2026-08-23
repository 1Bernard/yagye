defmodule YagyeCore.LedgerTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.Ledger
  alias YagyeCore.Ledger.Schemas.{Account, Entry}
  alias YagyeCore.Providers.Schemas.Provider
  alias YagyeCore.Repo
  alias YagyeCore.Settlement.Schemas.SettlementBatch

  defp batch_fixture(merchant, attrs \\ %{}) do
    provider = Fixtures.simulator_provider_fixture()

    Repo.insert!(
      SettlementBatch.changeset(%SettlementBatch{}, %{
        merchant_id: merchant.id,
        provider_id: provider.id,
        currency: Map.get(attrs, :currency, "GHS"),
        mode: Map.get(attrs, :mode, "simulation"),
        period_start: DateTime.add(DateTime.utc_now(), -86_400),
        period_end: DateTime.utc_now(),
        payment_count: Map.get(attrs, :payment_count, 3),
        gross_amount: Map.get(attrs, :gross_amount, 30_000)
      })
    )
  end

  describe "post_batch_approved/1" do
    setup do
      merchant = Fixtures.merchant_fixture()
      %{merchant: merchant}
    end

    test "creates a batch_approved entry", %{merchant: merchant} do
      batch = batch_fixture(merchant)
      assert {:ok, entry} = Ledger.post_batch_approved(batch)

      assert entry.entry_type == "batch_approved"
      assert entry.source_type == "settlement_batch"
      assert entry.source_id == batch.id
      assert entry.currency == batch.currency
      assert entry.mode == batch.mode
    end

    test "creates a debit posting on merchant_payable", %{merchant: merchant} do
      batch = batch_fixture(merchant)
      {:ok, entry} = Ledger.post_batch_approved(batch)

      postings =
        Repo.all(from p in YagyeCore.Ledger.Schemas.Posting, where: p.entry_id == ^entry.id)

      debit = Enum.find(postings, &(&1.direction == "debit"))

      assert debit != nil
      assert debit.amount == batch.gross_amount
      assert debit.currency == batch.currency

      account = Repo.get!(Account, debit.account_id)
      assert account.account_type == "merchant_payable"
      assert account.scope_id == batch.merchant_id
    end

    test "creates a credit posting on settlement_approved", %{merchant: merchant} do
      batch = batch_fixture(merchant)
      {:ok, entry} = Ledger.post_batch_approved(batch)

      postings =
        Repo.all(from p in YagyeCore.Ledger.Schemas.Posting, where: p.entry_id == ^entry.id)

      credit = Enum.find(postings, &(&1.direction == "credit"))

      assert credit != nil
      assert credit.amount == batch.gross_amount
      assert credit.currency == batch.currency

      account = Repo.get!(Account, credit.account_id)
      assert account.account_type == "settlement_approved"
      assert account.scope_id == batch.merchant_id
    end

    test "settlement_approved account is merchant-scoped with credit normal balance",
         %{merchant: merchant} do
      batch = batch_fixture(merchant)
      {:ok, _entry} = Ledger.post_batch_approved(batch)

      code = "settlement_approved:#{batch.merchant_id}:#{batch.currency}:#{batch.mode}"
      {:ok, account} = Ledger.get_account(code)

      assert account.scope_type == "merchant"
      assert account.normal_balance == "credit"
    end

    test "updates settlement_approved balance by gross_amount", %{merchant: merchant} do
      batch = batch_fixture(merchant, %{gross_amount: 50_000})
      {:ok, _entry} = Ledger.post_batch_approved(batch)

      code = "settlement_approved:#{batch.merchant_id}:#{batch.currency}:#{batch.mode}"
      {:ok, account} = Ledger.get_account(code)
      {:ok, balance} = Ledger.get_balance(account.id)

      assert balance == -50_000
    end

    test "decreases merchant_payable balance by gross_amount", %{merchant: merchant} do
      batch = batch_fixture(merchant, %{gross_amount: 25_000})
      {:ok, _entry} = Ledger.post_batch_approved(batch)

      code = "merchant_payable:#{batch.merchant_id}:#{batch.currency}:#{batch.mode}"
      {:ok, account} = Ledger.get_account(code)
      {:ok, balance} = Ledger.get_balance(account.id)

      assert balance == 25_000
    end

    test "is idempotent — calling twice returns the same entry", %{merchant: merchant} do
      batch = batch_fixture(merchant)
      {:ok, entry_a} = Ledger.post_batch_approved(batch)
      {:ok, entry_b} = Ledger.post_batch_approved(batch)

      assert entry_a.id == entry_b.id
    end

    test "two different batches produce independent entries", %{merchant: merchant} do
      batch_a = batch_fixture(merchant, %{gross_amount: 10_000})

      other_provider =
        Repo.insert!(
          Provider.changeset(%Provider{}, %{
            code: "other_#{System.unique_integer([:positive])}",
            display_name: "Other",
            adapter_module: "YagyeCore.Payments.Adapters.SimulatorAdapter",
            active: true
          })
        )

      batch_b =
        Repo.insert!(
          SettlementBatch.changeset(%SettlementBatch{}, %{
            merchant_id: merchant.id,
            provider_id: other_provider.id,
            currency: "GHS",
            mode: "simulation",
            period_start: DateTime.add(DateTime.utc_now(), -172_800),
            period_end: DateTime.add(DateTime.utc_now(), -86_400),
            payment_count: 1,
            gross_amount: 5_000
          })
        )

      {:ok, entry_a} = Ledger.post_batch_approved(batch_a)
      {:ok, entry_b} = Ledger.post_batch_approved(batch_b)

      assert entry_a.id != entry_b.id

      entries =
        Repo.all(from e in Entry, where: e.source_type == "settlement_batch")

      assert length(entries) == 2
    end
  end
end
