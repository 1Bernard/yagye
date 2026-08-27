defmodule YagyeCoreWeb.Controllers.Compliance.ComplianceControllerTest do
  use YagyeCoreWeb.ConnCase, async: true

  alias YagyeCore.Fixtures

  setup do
    merchant = Fixtures.merchant_fixture()

    {_key, write_key} =
      Fixtures.api_key_fixture(merchant, %{scopes: ["kyb:write"], mode: "simulation"})

    {_key, read_key} =
      Fixtures.api_key_fixture(merchant, %{scopes: ["kyb:read"], mode: "simulation"})

    %{merchant: merchant, raw_key: write_key, read_key: read_key}
  end

  defp json_post(conn, raw_key, path, body) do
    conn
    |> with_auth(raw_key)
    |> put_req_header("content-type", "application/json")
    |> post(path, body)
  end

  defp json_get(conn, raw_key, path) do
    conn
    |> with_auth(raw_key)
    |> put_req_header("content-type", "application/json")
    |> get(path)
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

    test "returns 422 when business_type is missing", %{
      conn: conn,
      merchant: merchant,
      raw_key: raw_key
    } do
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
      {_key, bad_key} =
        Fixtures.api_key_fixture(merchant, %{scopes: ["merchants:read"], mode: "simulation"})

      resp =
        conn
        |> with_auth(bad_key)
        |> put_req_header("content-type", "application/json")
        |> post("/v1/merchants/#{merchant.public_id}/onboarding", %{business_type: "saas"})

      assert resp.status == 403
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # POST /v1/merchants/:merchant_id/beneficial-owners
  # ──────────────────────────────────────────────────────────────────────────
  describe "POST /v1/merchants/:merchant_id/beneficial-owners" do
    test "returns 201 with beneficial owner data", %{
      conn: conn,
      merchant: merchant,
      raw_key: raw_key
    } do
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

    test "returns 422 when required fields are missing", %{
      conn: conn,
      merchant: merchant,
      raw_key: raw_key
    } do
      resp =
        json_post(conn, raw_key, "/v1/merchants/#{merchant.public_id}/beneficial-owners", %{
          ownership_bps: 1000
        })

      assert resp.status == 422
      body = Jason.decode!(resp.resp_body)
      assert body["error"]["code"] == "schema_validation_failed"
    end

    test "returns 422 when role is invalid", %{conn: conn, merchant: merchant, raw_key: raw_key} do
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
  # GET /v1/merchants/:merchant_id/beneficial-owners
  # ──────────────────────────────────────────────────────────────────────────
  describe "GET /v1/merchants/:merchant_id/beneficial-owners" do
    test "returns 200 with empty list when no owners", %{
      conn: conn,
      merchant: merchant,
      read_key: read_key
    } do
      resp = json_get(conn, read_key, "/v1/merchants/#{merchant.public_id}/beneficial-owners")

      assert resp.status == 200
      body = Jason.decode!(resp.resp_body)
      assert body["object"] == "list"
      assert body["data"] == []
      assert body["count"] == 0
    end

    test "returns 200 with owners after POST", %{
      conn: conn,
      merchant: merchant,
      raw_key: raw_key,
      read_key: read_key
    } do
      subject_ref = Fixtures.pii_vault_fixture()

      json_post(conn, raw_key, "/v1/merchants/#{merchant.public_id}/beneficial-owners", %{
        subject_ref: subject_ref,
        role: "ubo",
        ownership_bps: 5000
      })

      resp = json_get(conn, read_key, "/v1/merchants/#{merchant.public_id}/beneficial-owners")

      assert resp.status == 200
      body = Jason.decode!(resp.resp_body)
      assert body["count"] == 1
      assert hd(body["data"])["role"] == "ubo"
    end

    test "returns 403 with write key (wrong scope)", %{
      conn: conn,
      merchant: merchant,
      raw_key: raw_key
    } do
      resp = json_get(conn, raw_key, "/v1/merchants/#{merchant.public_id}/beneficial-owners")
      assert resp.status == 403
    end

    test "returns 404 for unknown merchant", %{conn: conn, read_key: read_key} do
      resp = json_get(conn, read_key, "/v1/merchants/mch_unknown/beneficial-owners")
      assert resp.status == 404
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # POST /v1/merchants/:merchant_id/documents
  # ──────────────────────────────────────────────────────────────────────────
  describe "POST /v1/merchants/:merchant_id/documents" do
    test "returns 201 with document data when s3_key provided", %{
      conn: conn,
      merchant: merchant,
      raw_key: raw_key
    } do
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

    test "returns 201 and generates s3_key when omitted", %{
      conn: conn,
      merchant: merchant,
      raw_key: raw_key
    } do
      resp =
        json_post(conn, raw_key, "/v1/merchants/#{merchant.public_id}/documents", %{
          kind: "id",
          checksum: "abc123",
          uploaded_by: "ops:usr_test"
        })

      assert resp.status == 201
      body = Jason.decode!(resp.resp_body)
      assert body["object"] == "kyb_document"
      assert body["kind"] == "id"
    end

    test "returns 422 when required fields are missing", %{
      conn: conn,
      merchant: merchant,
      raw_key: raw_key
    } do
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
          checksum: "csum",
          uploaded_by: "user:usr_test"
        })

      assert resp.status == 422
    end

    test "returns 404 when merchant does not exist", %{conn: conn, raw_key: raw_key} do
      resp =
        json_post(conn, raw_key, "/v1/merchants/mch_nonexistent/documents", %{
          kind: "id",
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
          checksum: "csum",
          uploaded_by: "user:usr_test"
        })

      assert resp.status == 401
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # GET /v1/merchants/:merchant_id/documents
  # ──────────────────────────────────────────────────────────────────────────
  describe "GET /v1/merchants/:merchant_id/documents" do
    test "returns 200 with empty list when no documents", %{
      conn: conn,
      merchant: merchant,
      read_key: read_key
    } do
      resp = json_get(conn, read_key, "/v1/merchants/#{merchant.public_id}/documents")

      assert resp.status == 200
      body = Jason.decode!(resp.resp_body)
      assert body["object"] == "list"
      assert body["count"] == 0
    end

    test "returns 200 with documents after POST", %{
      conn: conn,
      merchant: merchant,
      raw_key: raw_key,
      read_key: read_key
    } do
      json_post(conn, raw_key, "/v1/merchants/#{merchant.public_id}/documents", %{
        kind: "incorporation",
        checksum: "c1",
        uploaded_by: "u"
      })

      resp = json_get(conn, read_key, "/v1/merchants/#{merchant.public_id}/documents")
      assert resp.status == 200
      body = Jason.decode!(resp.resp_body)
      assert body["count"] == 1
    end

    test "returns 403 with write key", %{conn: conn, merchant: merchant, raw_key: raw_key} do
      resp = json_get(conn, raw_key, "/v1/merchants/#{merchant.public_id}/documents")
      assert resp.status == 403
    end

    test "returns 404 for unknown merchant", %{conn: conn, read_key: read_key} do
      resp = json_get(conn, read_key, "/v1/merchants/mch_unknown/documents")
      assert resp.status == 404
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # GET /v1/merchants/:merchant_id/screening-status
  # ──────────────────────────────────────────────────────────────────────────
  describe "GET /v1/merchants/:merchant_id/screening-status" do
    test "returns 200 with empty subjects before any owners", %{
      conn: conn,
      merchant: merchant,
      read_key: read_key
    } do
      resp = json_get(conn, read_key, "/v1/merchants/#{merchant.public_id}/screening-status")

      assert resp.status == 200
      body = Jason.decode!(resp.resp_body)
      assert body["object"] == "screening_status"
      assert body["subjects"] == []
      assert body["open_hits"] == []
    end

    test "returns pending subject after adding a beneficial owner", %{
      conn: conn,
      merchant: merchant,
      raw_key: raw_key,
      read_key: read_key
    } do
      subject_ref = Fixtures.pii_vault_fixture()

      json_post(conn, raw_key, "/v1/merchants/#{merchant.public_id}/beneficial-owners", %{
        subject_ref: subject_ref,
        role: "ubo",
        ownership_bps: 5000
      })

      resp = json_get(conn, read_key, "/v1/merchants/#{merchant.public_id}/screening-status")
      assert resp.status == 200
      body = Jason.decode!(resp.resp_body)
      assert length(body["subjects"]) == 1
      assert hd(body["subjects"])["screening_status"] == "pending"
    end

    test "returns 403 with write key", %{conn: conn, merchant: merchant, raw_key: raw_key} do
      resp = json_get(conn, raw_key, "/v1/merchants/#{merchant.public_id}/screening-status")
      assert resp.status == 403
    end

    test "returns 404 for unknown merchant", %{conn: conn, read_key: read_key} do
      resp = json_get(conn, read_key, "/v1/merchants/mch_unknown/screening-status")
      assert resp.status == 404
    end
  end
end
