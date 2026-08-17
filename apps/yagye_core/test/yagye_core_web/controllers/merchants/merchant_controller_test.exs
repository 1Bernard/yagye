defmodule YagyeCoreWeb.Controllers.Merchants.MerchantControllerTest do
  use YagyeCoreWeb.ConnCase, async: true

  alias YagyeCore.Fixtures

  @valid_attrs %{
    legal_name: "Acme Payments Ltd",
    trading_name: "Acme Pay",
    country: "GB",
    default_currency: "GBP"
  }

  # Sets up an approved merchant and a wildcard simulation key for each test.
  setup do
    merchant = Fixtures.approved_merchant_fixture()
    {_key, raw_key} = Fixtures.api_key_fixture(merchant, %{scopes: ["*"], mode: "simulation"})
    %{merchant: merchant, raw_key: raw_key}
  end

  describe "POST /v1/merchants" do
    test "creates a merchant and returns 201", %{conn: conn, raw_key: raw_key} do
      resp =
        conn
        |> with_auth(raw_key)
        |> put_req_header("content-type", "application/json")
        |> post("/v1/merchants", @valid_attrs)

      assert resp.status == 201
      body = Jason.decode!(resp.resp_body)
      assert body["object"] == "merchant"
      assert body["legal_name"] == "Acme Payments Ltd"
      assert body["status"] == "registered"
      assert String.starts_with?(body["id"], "mch_")
    end

    test "returns 422 when required fields are missing", %{conn: conn, raw_key: raw_key} do
      resp =
        conn
        |> with_auth(raw_key)
        |> put_req_header("content-type", "application/json")
        |> post("/v1/merchants", %{legal_name: "Incomplete"})

      assert resp.status == 422
      body = Jason.decode!(resp.resp_body)
      assert %{"error" => %{"type" => "invalid_request_error", "code" => "schema_validation_failed"}} = body
    end

    test "returns 401 without an API key", %{conn: conn} do
      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/merchants", @valid_attrs)

      assert resp.status == 401
    end

    test "returns 401 with an invalid API key", %{conn: conn} do
      resp =
        conn
        |> with_auth("totally_wrong_key_aaaaaaaaaaaaaaaaaaaaaaa")
        |> put_req_header("content-type", "application/json")
        |> post("/v1/merchants", @valid_attrs)

      assert resp.status == 401
    end
  end

  describe "GET /v1/merchants/:id" do
    test "returns the merchant by public_id", %{conn: conn, merchant: merchant, raw_key: raw_key} do
      resp =
        conn
        |> with_auth(raw_key)
        |> get("/v1/merchants/#{merchant.public_id}")

      assert resp.status == 200
      body = Jason.decode!(resp.resp_body)
      assert body["id"] == merchant.public_id
      assert body["object"] == "merchant"
    end

    test "returns 404 for unknown public_id", %{conn: conn, raw_key: raw_key} do
      resp =
        conn
        |> with_auth(raw_key)
        |> get("/v1/merchants/mch_doesnotexist")

      assert resp.status == 404
    end

    test "returns 401 without auth", %{conn: conn, merchant: merchant} do
      resp = get(conn, "/v1/merchants/#{merchant.public_id}")
      assert resp.status == 401
    end
  end

  describe "POST /v1/merchants/:merchant_id/approve" do
    test "approves a registered merchant", %{conn: conn, raw_key: raw_key} do
      new_merchant = Fixtures.merchant_fixture()

      resp =
        conn
        |> with_auth(raw_key)
        |> post("/v1/merchants/#{new_merchant.public_id}/approve")

      assert resp.status == 200
      body = Jason.decode!(resp.resp_body)
      assert body["status"] == "approved"
    end

    test "returns 422 when merchant is already approved", %{
      conn: conn,
      merchant: merchant,
      raw_key: raw_key
    } do
      resp =
        conn
        |> with_auth(raw_key)
        |> post("/v1/merchants/#{merchant.public_id}/approve")

      assert resp.status == 422
    end

    test "returns 404 for unknown merchant", %{conn: conn, raw_key: raw_key} do
      resp =
        conn
        |> with_auth(raw_key)
        |> post("/v1/merchants/mch_ghost/approve")

      assert resp.status == 404
    end
  end
end
