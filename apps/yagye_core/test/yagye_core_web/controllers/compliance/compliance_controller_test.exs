defmodule YagyeCoreWeb.Controllers.Compliance.ComplianceControllerTest do
  use YagyeCoreWeb.ConnCase, async: true

  alias YagyeCore.Fixtures

  setup do
    merchant = Fixtures.merchant_fixture()
    {_key, raw_key} = Fixtures.api_key_fixture(merchant, %{scopes: ["kyb:write"], mode: "simulation"})
    %{merchant: merchant, raw_key: raw_key}
  end

  defp json_post(conn, raw_key, path, body) do
    conn
    |> with_auth(raw_key)
    |> put_req_header("content-type", "application/json")
    |> post(path, body)
  end

  # ──────────────────────────────────────────────────────────────────────────
  # POST /v1/merchants/:merchant_id/onboarding
  # ──────────────────────────────────────────────────────────────────────────
  describe "POST /v1/merchants/:merchant_id/onboarding" do
    test "returns 200 with merchant data", %{conn: conn, merchant: merchant, raw_key: raw_key} do
      resp =
        json_post(conn, raw_key, "/v1/merchants/#{merchant.public_id}/onboarding", %{
          business_type: "ecommerce",
          website_url: "https://acmepay.com",
          expected_monthly_volume_minor: 5_000_000,
          expected_monthly_volume_currency: "GBP"
        })

      assert resp.status == 200
      body = Jason.decode!(resp.resp_body)
      assert body["object"] == "merchant"
      assert body["id"] == merchant.public_id
      assert is_binary(body["onboarding_state"])
    end

    test "returns 422 when business_type is missing", %{conn: conn, merchant: merchant, raw_key: raw_key} do
      resp =
        json_post(conn, raw_key, "/v1/merchants/#{merchant.public_id}/onboarding", %{
          website_url: "https://example.com"
        })

      assert resp.status == 422
      body = Jason.decode!(resp.resp_body)
      assert body["error"]["code"] == "schema_validation_failed"
    end

    test "returns 404 when merchant does not exist", %{conn: conn, raw_key: raw_key} do
      resp =
        json_post(conn, raw_key, "/v1/merchants/mch_nonexistent/onboarding", %{
          business_type: "saas"
        })

      assert resp.status == 404
    end

    test "returns 401 without auth", %{conn: conn, merchant: merchant} do
      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/merchants/#{merchant.public_id}/onboarding", %{business_type: "saas"})

      assert resp.status == 401
    end

    test "returns 403 when scope is missing", %{conn: conn, merchant: merchant} do
      {_key, read_key} =
        Fixtures.api_key_fixture(merchant, %{scopes: ["merchants:read"], mode: "simulation"})

      resp =
        conn
        |> with_auth(read_key)
        |> put_req_header("content-type", "application/json")
        |> post("/v1/merchants/#{merchant.public_id}/onboarding", %{business_type: "saas"})

      assert resp.status == 403
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # POST /v1/merchants/:merchant_id/beneficial-owners
  # ──────────────────────────────────────────────────────────────────────────
  describe "POST /v1/merchants/:merchant_id/beneficial-owners" do
    test "returns 201 with beneficial owner data", %{conn: conn, merchant: merchant, raw_key: raw_key} do
      subject_ref = Fixtures.pii_vault_fixture()

      resp =
        json_post(conn, raw_key, "/v1/merchants/#{merchant.public_id}/beneficial-owners", %{
          subject_ref: subject_ref,
          role: "ubo",
          ownership_bps: 5000
        })

      assert resp.status == 201
      body = Jason.decode!(resp.resp_body)
      assert body["object"] == "beneficial_owner"
      assert body["role"] == "ubo"
      assert body["ownership_bps"] == 5000
    end

    test "returns 422 when required fields are missing", %{conn: conn, merchant: merchant, raw_key: raw_key} do
      resp =
        json_post(conn, raw_key, "/v1/merchants/#{merchant.public_id}/beneficial-owners", %{
          ownership_bps: 1000
        })

      assert resp.status == 422
      body = Jason.decode!(resp.resp_body)
      assert body["error"]["code"] == "schema_validation_failed"
    end

    test "returns 422 when role is invalid", %{conn: conn, merchant: merchant, raw_key: raw_key} do
      # CastAndValidate enforces the enum at the HTTP layer — no pii_vault entry needed
      resp =
        json_post(conn, raw_key, "/v1/merchants/#{merchant.public_id}/beneficial-owners", %{
          subject_ref: Uniq.UUID.uuid7(),
          role: "janitor"
        })

      assert resp.status == 422
    end

    test "returns 404 when merchant does not exist", %{conn: conn, raw_key: raw_key} do
      resp =
        json_post(conn, raw_key, "/v1/merchants/mch_nonexistent/beneficial-owners", %{
          subject_ref: Uniq.UUID.uuid7(),
          role: "director"
        })

      assert resp.status == 404
    end

    test "returns 401 without auth", %{conn: conn, merchant: merchant} do
      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/merchants/#{merchant.public_id}/beneficial-owners", %{
          subject_ref: Uniq.UUID.uuid7(),
          role: "ubo"
        })

      assert resp.status == 401
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # POST /v1/merchants/:merchant_id/documents
  # ──────────────────────────────────────────────────────────────────────────
  describe "POST /v1/merchants/:merchant_id/documents" do
    test "returns 201 with document data", %{conn: conn, merchant: merchant, raw_key: raw_key} do
      resp =
        json_post(conn, raw_key, "/v1/merchants/#{merchant.public_id}/documents", %{
          kind: "incorporation",
          s3_key: "kyb/mch_abc/cert.pdf",
          checksum: "abc123def456",
          uploaded_by: "user:usr_test"
        })

      assert resp.status == 201
      body = Jason.decode!(resp.resp_body)
      assert body["object"] == "kyb_document"
      assert body["kind"] == "incorporation"
    end

    test "returns 422 when required fields are missing", %{conn: conn, merchant: merchant, raw_key: raw_key} do
      resp =
        json_post(conn, raw_key, "/v1/merchants/#{merchant.public_id}/documents", %{
          kind: "id"
        })

      assert resp.status == 422
      body = Jason.decode!(resp.resp_body)
      assert body["error"]["code"] == "schema_validation_failed"
    end

    test "returns 422 when kind is invalid", %{conn: conn, merchant: merchant, raw_key: raw_key} do
      resp =
        json_post(conn, raw_key, "/v1/merchants/#{merchant.public_id}/documents", %{
          kind: "selfie",
          s3_key: "kyb/doc.pdf",
          checksum: "csum",
          uploaded_by: "user:usr_test"
        })

      assert resp.status == 422
    end

    test "returns 404 when merchant does not exist", %{conn: conn, raw_key: raw_key} do
      resp =
        json_post(conn, raw_key, "/v1/merchants/mch_nonexistent/documents", %{
          kind: "id",
          s3_key: "kyb/doc.pdf",
          checksum: "csum",
          uploaded_by: "user:usr_test"
        })

      assert resp.status == 404
    end

    test "returns 401 without auth", %{conn: conn, merchant: merchant} do
      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/merchants/#{merchant.public_id}/documents", %{
          kind: "id",
          s3_key: "kyb/doc.pdf",
          checksum: "csum",
          uploaded_by: "user:usr_test"
        })

      assert resp.status == 401
    end
  end
end
