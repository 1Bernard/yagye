defmodule YagyeCoreWeb.Controllers.Disputes.RefundControllerTest do
  use YagyeCoreWeb.ConnCase, async: true

  alias YagyeCore.Fixtures

  setup do
    merchant = Fixtures.approved_merchant_fixture()

    {_key, raw_key} =
      Fixtures.api_key_fixture(merchant, %{
        scopes: ["payments:write", "payments:read"],
        mode: "simulation"
      })

    %{merchant: merchant, raw_key: raw_key}
  end

  defp json_post(conn, raw_key, path, body) do
    conn
    |> with_auth(raw_key)
    |> put_req_header("content-type", "application/json")
    |> post(path, body)
  end

  # ── POST /v1/payments/:payment_id/refunds ─────────────────────────────────────

  describe "POST /v1/payments/:payment_id/refunds" do
    test "returns 201 and issues a refund", %{conn: conn, merchant: merchant, raw_key: raw_key} do
      payment = Fixtures.succeeded_payment_fixture(merchant, %{amount: 10_000})

      resp =
        json_post(conn, raw_key, "/v1/payments/#{payment.public_id}/refunds", %{
          amount: 10_000,
          reason: "customer_request"
        })

      assert resp.status == 201
      body = Jason.decode!(resp.resp_body)
      assert body["object"] == "refund"
      assert body["amount"] == 10_000
      assert body["state"] == "succeeded"
      assert body["reason"] == "customer_request"
      assert body["dispute_id"] == nil
      assert String.starts_with?(body["id"], "ref_")
    end

    test "returns 201 for partial refund", %{conn: conn, merchant: merchant, raw_key: raw_key} do
      payment = Fixtures.succeeded_payment_fixture(merchant, %{amount: 10_000})

      resp =
        json_post(conn, raw_key, "/v1/payments/#{payment.public_id}/refunds", %{
          amount: 5_000,
          reason: "duplicate"
        })

      assert resp.status == 201
      body = Jason.decode!(resp.resp_body)
      assert body["amount"] == 5_000
    end

    test "retracts open dispute when payment is disputed", %{
      conn: conn,
      merchant: merchant,
      raw_key: raw_key
    } do
      payment = Fixtures.succeeded_payment_fixture(merchant)

      # Inject a dispute first
      %{"id" => dispute_id} =
        json_post(conn, raw_key, "/v1/payments/#{payment.public_id}/disputes", %{
          network: "MTN",
          reason: "fraud"
        })
        |> Map.fetch!(:resp_body)
        |> Jason.decode!()

      resp =
        json_post(conn, raw_key, "/v1/payments/#{payment.public_id}/refunds", %{
          amount: payment.amount
        })

      assert resp.status == 201
      body = Jason.decode!(resp.resp_body)
      assert body["reason"] == "dispute_retracted"
      assert body["dispute_id"] == dispute_id
    end

    test "returns 422 when amount exceeds original", %{
      conn: conn,
      merchant: merchant,
      raw_key: raw_key
    } do
      payment = Fixtures.succeeded_payment_fixture(merchant, %{amount: 10_000})

      resp =
        json_post(conn, raw_key, "/v1/payments/#{payment.public_id}/refunds", %{
          amount: 99_999
        })

      assert resp.status == 422
      body = Jason.decode!(resp.resp_body)
      assert body["error"]["code"] == "amount_exceeds_original"
    end

    test "returns 422 when payment is not refundable", %{
      conn: conn,
      merchant: merchant,
      raw_key: raw_key
    } do
      payment = Fixtures.payment_fixture(merchant)

      resp =
        json_post(conn, raw_key, "/v1/payments/#{payment.public_id}/refunds", %{
          amount: 1_000
        })

      assert resp.status == 422
      body = Jason.decode!(resp.resp_body)
      assert body["error"]["code"] == "not_refundable"
    end

    test "returns 404 for unknown payment", %{conn: conn, raw_key: raw_key} do
      resp = json_post(conn, raw_key, "/v1/payments/pay_unknown/refunds", %{amount: 1_000})
      assert resp.status == 404
    end

    test "returns 401 without auth", %{conn: conn, merchant: merchant} do
      payment = Fixtures.succeeded_payment_fixture(merchant)

      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/payments/#{payment.public_id}/refunds", %{amount: 1_000})

      assert resp.status == 401
    end
  end

  # ── GET /v1/refunds/:id ───────────────────────────────────────────────────────

  describe "GET /v1/refunds/:id" do
    test "returns 200 with refund data", %{conn: conn, merchant: merchant, raw_key: raw_key} do
      payment = Fixtures.succeeded_payment_fixture(merchant, %{amount: 10_000})

      %{"id" => refund_id} =
        json_post(conn, raw_key, "/v1/payments/#{payment.public_id}/refunds", %{amount: 10_000})
        |> Map.fetch!(:resp_body)
        |> Jason.decode!()

      resp =
        conn
        |> with_auth(raw_key)
        |> get("/v1/refunds/#{refund_id}")

      assert resp.status == 200
      body = Jason.decode!(resp.resp_body)
      assert body["id"] == refund_id
      assert body["object"] == "refund"
    end

    test "returns 404 for unknown refund", %{conn: conn, raw_key: raw_key} do
      resp =
        conn
        |> with_auth(raw_key)
        |> get("/v1/refunds/ref_doesnotexist")

      assert resp.status == 404
    end
  end
end
