defmodule YagyeCoreWeb.Controllers.Public.ReceiptControllerTest do
  use YagyeCoreWeb.ConnCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Repo

  describe "GET /r/:public_id" do
    test "returns 200 HTML for a succeeded payment", %{conn: conn} do
      merchant = Fixtures.merchant_fixture()
      payment = Fixtures.succeeded_payment_fixture(merchant, %{amount: 5000, currency: "GHS"})

      resp = get(conn, "/r/#{payment.public_id}")

      assert resp.status == 200
      assert resp.resp_body =~ merchant.trading_name
      assert resp.resp_body =~ "GH₵"
      assert resp.resp_body =~ "Thank you for your payment"
    end

    test "returns 404 for unknown public_id", %{conn: conn} do
      resp = get(conn, "/r/pay_doesnotexist")
      assert resp.status == 404
    end

    test "returns 404 for a payment that is not succeeded", %{conn: conn} do
      merchant = Fixtures.merchant_fixture()
      payment = Fixtures.payment_fixture(merchant, %{amount: 1000, currency: "GHS"})

      assert payment.state == "created"

      resp = get(conn, "/r/#{payment.public_id}")
      assert resp.status == 404
    end

    test "shows custom_note when set in receipt_settings", %{conn: conn} do
      merchant = Fixtures.merchant_fixture()

      {:ok, _} =
        Repo.get_by(Merchant, public_id: merchant.public_id)
        |> Merchant.changeset(%{
          receipt_settings: %{"custom_note" => "Thank you for shopping with us!"}
        })
        |> Repo.update()

      payment = Fixtures.succeeded_payment_fixture(merchant, %{amount: 2500, currency: "GHS"})

      resp = get(conn, "/r/#{payment.public_id}")
      assert resp.status == 200
      assert resp.resp_body =~ "Thank you for shopping with us!"
    end

    test "hides powered_by when show_powered_by is false", %{conn: conn} do
      merchant = Fixtures.merchant_fixture()

      {:ok, _} =
        Repo.get_by(Merchant, public_id: merchant.public_id)
        |> Merchant.changeset(%{
          receipt_settings: %{"show_powered_by" => false}
        })
        |> Repo.update()

      payment = Fixtures.succeeded_payment_fixture(merchant)

      resp = get(conn, "/r/#{payment.public_id}")
      assert resp.status == 200
      refute resp.resp_body =~ "Powered by Yagye"
    end
  end
end
