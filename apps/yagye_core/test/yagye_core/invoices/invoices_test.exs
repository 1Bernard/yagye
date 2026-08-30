defmodule YagyeCore.Invoices.InvoicesTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.{Fixtures, Invoices}
  alias YagyeCore.Invoices.Schemas.Invoice

  defp base_attrs(_merchant, customer, overrides \\ %{}) do
    Map.merge(
      %{
        mode: "simulation",
        customer_id: customer.id,
        currency: "GHS",
        number: "INV-#{System.unique_integer([:positive])}",
        issue_date: ~D[2026-08-30],
        due_date: ~D[2026-09-30],
        line_items: [
          %{
            description: "Service fee",
            quantity: 1,
            unit_amount: 10_000,
            tax_rate_bps: 1500,
            total_amount: 11_500
          }
        ]
      },
      overrides
    )
  end

  # ── create_invoice/2 ───────────────────────────────────────────────────────

  describe "create_invoice/2" do
    test "creates invoice with computed totals" do
      merchant = Fixtures.merchant_fixture()
      customer = Fixtures.customer_fixture(merchant)

      assert {:ok, invoice} = Invoices.create_invoice(merchant.id, base_attrs(merchant, customer))

      assert invoice.state == "draft"
      assert invoice.subtotal_amount == 10_000
      assert invoice.tax_amount == 1_500
      assert invoice.total_amount == 11_500
      assert invoice.amount_due == 11_500
      assert invoice.amount_paid == 0
      assert String.starts_with?(invoice.public_id, "inv_")
    end

    test "generates unique invoice public_id" do
      merchant = Fixtures.merchant_fixture()
      customer = Fixtures.customer_fixture(merchant)

      {:ok, inv1} = Invoices.create_invoice(merchant.id, base_attrs(merchant, customer))
      {:ok, inv2} = Invoices.create_invoice(merchant.id, base_attrs(merchant, customer))

      assert inv1.public_id != inv2.public_id
    end

    test "rejects duplicate invoice number per merchant" do
      merchant = Fixtures.merchant_fixture()
      customer = Fixtures.customer_fixture(merchant)
      attrs = base_attrs(merchant, customer, %{number: "INV-DUP-001"})

      assert {:ok, _} = Invoices.create_invoice(merchant.id, attrs)
      assert {:error, _} = Invoices.create_invoice(merchant.id, attrs)
    end

    test "rejects invalid mode" do
      merchant = Fixtures.merchant_fixture()
      customer = Fixtures.customer_fixture(merchant)

      assert {:error, changeset} =
               Invoices.create_invoice(
                 merchant.id,
                 base_attrs(merchant, customer, %{mode: "staging"})
               )

      assert "is invalid" in errors_on(changeset).mode
    end
  end

  # ── issue_invoice/1 ────────────────────────────────────────────────────────

  describe "issue_invoice/1" do
    test "transitions draft to open" do
      merchant = Fixtures.merchant_fixture()
      customer = Fixtures.customer_fixture(merchant)
      {:ok, invoice} = Invoices.create_invoice(merchant.id, base_attrs(merchant, customer))

      assert {:ok, updated} = Invoices.issue_invoice(invoice.public_id)
      assert updated.state == "open"
    end

    test "returns not_found for unknown public_id" do
      assert {:error, :not_found} = Invoices.issue_invoice("inv_doesnotexist")
    end
  end

  # ── void_invoice/1 ────────────────────────────────────────────────────────

  describe "void_invoice/1" do
    test "voids a draft invoice" do
      merchant = Fixtures.merchant_fixture()
      customer = Fixtures.customer_fixture(merchant)
      {:ok, invoice} = Invoices.create_invoice(merchant.id, base_attrs(merchant, customer))

      assert {:ok, voided} = Invoices.void_invoice(invoice.public_id)
      assert voided.state == "void"
      assert voided.voided_at != nil
    end

    test "cannot void a paid invoice" do
      merchant = Fixtures.merchant_fixture()
      customer = Fixtures.customer_fixture(merchant)
      {:ok, invoice} = Invoices.create_invoice(merchant.id, base_attrs(merchant, customer))
      {:ok, _} = Invoices.issue_invoice(invoice.public_id)

      # force to paid via direct DB update for testing
      YagyeCore.Repo.update_all(
        from(i in Invoice, where: i.id == ^invoice.id),
        set: [state: "paid"]
      )

      {:ok, paid_invoice} = Invoices.get_invoice(invoice.public_id)
      assert {:error, changeset} = Invoices.void_invoice(paid_invoice.public_id)
      assert "cannot transition from paid to void" in errors_on(changeset).state
    end
  end

  # ── list_invoices/2 ────────────────────────────────────────────────────────

  describe "list_invoices/2" do
    test "returns invoices for merchant" do
      merchant = Fixtures.merchant_fixture()
      other_merchant = Fixtures.merchant_fixture()
      customer = Fixtures.customer_fixture(merchant)

      Invoices.create_invoice(merchant.id, base_attrs(merchant, customer))
      Invoices.create_invoice(merchant.id, base_attrs(merchant, customer))
      Invoices.create_invoice(other_merchant.id, base_attrs(other_merchant, customer))

      {:ok, invoices} = Invoices.list_invoices(merchant.id)
      assert length(invoices) == 2
      assert Enum.all?(invoices, &(&1.merchant_id == merchant.id))
    end

    test "filters by state" do
      merchant = Fixtures.merchant_fixture()
      customer = Fixtures.customer_fixture(merchant)
      {:ok, inv} = Invoices.create_invoice(merchant.id, base_attrs(merchant, customer))
      Invoices.issue_invoice(inv.public_id)

      {:ok, drafts} = Invoices.list_invoices(merchant.id, state: "draft")
      {:ok, open} = Invoices.list_invoices(merchant.id, state: "open")

      assert drafts == []
      assert length(open) == 1
    end
  end
end
