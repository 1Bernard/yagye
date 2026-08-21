defmodule YagyeCoreWeb.Controllers.Disputes.DisputeControllerTest do
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

  # ── POST /v1/payments/:payment_id/disputes ───────────────────────────────────

  describe "POST /v1/payments/:payment_id/disputes" do
    test "returns 201 and opens a dispute", %{conn: conn, merchant: merchant, raw_key: raw_key} do
      payment = Fixtures.succeeded_payment_fixture(merchant)

      resp =
        json_post(conn, raw_key, "/v1/payments/#{payment.public_id}/disputes", %{
          network: "MTN",
          reason: "fraud"
        })

      assert resp.status == 201
      body = Jason.decode!(resp.resp_body)
      assert body["object"] == "dispute"
      assert body["network"] == "MTN"
      assert body["reason"] == "fraud"
      assert body["stage"] == "opened"
      assert body["outcome"] == nil
      assert String.starts_with?(body["id"], "dsp_")
    end

    test "returns 422 when payment is not succeeded", %{
      conn: conn,
      merchant: merchant,
      raw_key: raw_key
    } do
      payment = Fixtures.payment_fixture(merchant)

      resp =
        json_post(conn, raw_key, "/v1/payments/#{payment.public_id}/disputes", %{
          network: "VISA",
          reason: "fraud"
        })

      assert resp.status == 422
      body = Jason.decode!(resp.resp_body)
      assert body["error"]["code"] == "not_disputable"
    end

    test "returns 404 for unknown payment", %{conn: conn, raw_key: raw_key} do
      resp =
        json_post(conn, raw_key, "/v1/payments/pay_unknown/disputes", %{
          network: "MTN",
          reason: "fraud"
        })

      assert resp.status == 404
    end

    test "returns 422 on schema validation failure", %{
      conn: conn,
      merchant: merchant,
      raw_key: raw_key
    } do
      payment = Fixtures.succeeded_payment_fixture(merchant)

      resp =
        json_post(conn, raw_key, "/v1/payments/#{payment.public_id}/disputes", %{
          network: "MTN"
        })

      assert resp.status == 422
      body = Jason.decode!(resp.resp_body)
      assert body["error"]["code"] == "schema_validation_failed"
    end

    test "returns 401 without auth", %{conn: conn, merchant: merchant} do
      payment = Fixtures.succeeded_payment_fixture(merchant)

      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/payments/#{payment.public_id}/disputes", %{network: "MTN", reason: "fraud"})

      assert resp.status == 401
    end
  end

  # ── GET /v1/disputes/:id ─────────────────────────────────────────────────────

  describe "GET /v1/disputes/:id" do
    test "returns 200 with dispute data", %{conn: conn, merchant: merchant, raw_key: raw_key} do
      payment = Fixtures.succeeded_payment_fixture(merchant)

      %{"id" => dispute_id} =
        json_post(conn, raw_key, "/v1/payments/#{payment.public_id}/disputes", %{
          network: "VISA",
          reason: "duplicate"
        })
        |> Map.fetch!(:resp_body)
        |> Jason.decode!()

      resp =
        conn
        |> with_auth(raw_key)
        |> get("/v1/disputes/#{dispute_id}")

      assert resp.status == 200
      body = Jason.decode!(resp.resp_body)
      assert body["id"] == dispute_id
      assert body["object"] == "dispute"
    end

    test "returns 404 for unknown dispute", %{conn: conn, raw_key: raw_key} do
      resp =
        conn
        |> with_auth(raw_key)
        |> get("/v1/disputes/dsp_doesnotexist")

      assert resp.status == 404
    end
  end
end
