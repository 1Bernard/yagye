defmodule YagyeCoreWeb.Controllers.Payments.PaymentControllerTest do
  use YagyeCoreWeb.ConnCase, async: true

  alias YagyeCore.Fixtures

  setup do
    merchant = Fixtures.merchant_fixture()

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

  # ──────────────────────────────────────────────────────────────────────────
  # POST /v1/payments
  # ──────────────────────────────────────────────────────────────────────────
  describe "POST /v1/payments" do
    test "returns 201 with payment data", %{conn: conn, raw_key: raw_key} do
      resp =
        json_post(conn, raw_key, "/v1/payments", %{
          amount: 10_000,
          currency: "GHS",
          rail: "fiat_provider",
          method: "mobile_money",
          description: "Test payment"
        })

      assert resp.status == 201
      body = Jason.decode!(resp.resp_body)
      assert body["object"] == "payment"
      assert body["amount"] == 10_000
      assert body["currency"] == "GHS"
      assert body["state"] == "created"
      assert body["mode"] == "simulation"
      assert body["rail"] == "fiat_provider"
      assert String.starts_with?(body["id"], "pay_")
    end

    test "returns 422 when required fields are missing", %{conn: conn, raw_key: raw_key} do
      resp = json_post(conn, raw_key, "/v1/payments", %{amount: 100})

      assert resp.status == 422
      body = Jason.decode!(resp.resp_body)
      assert body["error"]["code"] == "schema_validation_failed"
    end

    test "returns 422 when rail is invalid", %{conn: conn, raw_key: raw_key} do
      resp =
        json_post(conn, raw_key, "/v1/payments", %{
          amount: 100,
          currency: "GHS",
          rail: "crypto"
        })

      assert resp.status == 422
      body = Jason.decode!(resp.resp_body)
      assert body["error"]["code"] == "schema_validation_failed"
    end

    test "returns 401 without auth", %{conn: conn} do
      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/payments", %{amount: 100, currency: "GHS", rail: "fiat_provider"})

      assert resp.status == 401
    end

    test "returns 403 when scope is missing", %{conn: conn, merchant: merchant} do
      {_key, read_only_key} =
        Fixtures.api_key_fixture(merchant, %{scopes: ["merchants:read"], mode: "simulation"})

      resp =
        conn
        |> with_auth(read_only_key)
        |> put_req_header("content-type", "application/json")
        |> post("/v1/payments", %{amount: 100, currency: "GHS", rail: "fiat_provider"})

      assert resp.status == 403
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # GET /v1/payments/:id
  # ──────────────────────────────────────────────────────────────────────────
  describe "GET /v1/payments/:id" do
    test "returns 200 with payment data", %{conn: conn, merchant: merchant, raw_key: raw_key} do
      payment = Fixtures.payment_fixture(merchant)

      resp =
        conn
        |> with_auth(raw_key)
        |> get("/v1/payments/#{payment.public_id}")

      assert resp.status == 200
      body = Jason.decode!(resp.resp_body)
      assert body["id"] == payment.public_id
      assert body["object"] == "payment"
    end

    test "returns 404 for unknown payment", %{conn: conn, raw_key: raw_key} do
      resp =
        conn
        |> with_auth(raw_key)
        |> get("/v1/payments/pay_nonexistent")

      assert resp.status == 404
    end

    test "returns 401 without auth", %{conn: conn, merchant: merchant} do
      payment = Fixtures.payment_fixture(merchant)

      resp = get(conn, "/v1/payments/#{payment.public_id}")

      assert resp.status == 401
    end
  end
end
