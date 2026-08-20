defmodule YagyeCoreWeb.Controllers.ApiKeys.ApiKeyControllerTest do
  use YagyeCoreWeb.ConnCase, async: true

  alias YagyeCore.Fixtures

  setup do
    merchant = Fixtures.approved_merchant_fixture()
    {_key, raw_key} = Fixtures.api_key_fixture(merchant, %{scopes: ["*"], mode: "simulation"})
    %{merchant: merchant, raw_key: raw_key}
  end

  describe "POST /v1/merchants/:merchant_id/keys" do
    test "issues a secret key and returns raw key in response", %{
      conn: conn,
      merchant: merchant,
      raw_key: raw_key
    } do
      resp =
        conn
        |> with_auth(raw_key)
        |> put_req_header("content-type", "application/json")
        |> post("/v1/merchants/#{merchant.public_id}/keys", %{
          kind: "secret",
          mode: "simulation",
          scopes: ["merchants:read"]
        })

      assert resp.status == 201
      body = Jason.decode!(resp.resp_body)
      assert body["object"] == "api_key"
      assert body["kind"] == "secret"
      assert String.starts_with?(body["id"], "key_")
      # raw key present on creation only
      assert is_binary(body["key"])
      assert String.length(body["key"]) == 43
    end

    test "issues a publishable key", %{conn: conn, merchant: merchant, raw_key: raw_key} do
      resp =
        conn
        |> with_auth(raw_key)
        |> put_req_header("content-type", "application/json")
        |> post("/v1/merchants/#{merchant.public_id}/keys", %{
          kind: "publishable",
          mode: "simulation",
          scopes: []
        })

      assert resp.status == 201
      body = Jason.decode!(resp.resp_body)
      assert body["kind"] == "publishable"
      # publishable key: key == key_prefix (24 chars)
      assert String.length(body["key"]) == 24
    end

    test "returns 403 when a publishable key attempts to issue a key", %{
      conn: conn,
      merchant: merchant
    } do
      {_key, pub_raw_key} =
        Fixtures.api_key_fixture(merchant, %{kind: "publishable", scopes: ["api_keys:write"]})

      resp =
        conn
        |> with_auth(pub_raw_key)
        |> put_req_header("content-type", "application/json")
        |> post("/v1/merchants/#{merchant.public_id}/keys", %{
          kind: "secret",
          mode: "simulation",
          scopes: []
        })

      assert resp.status == 403
      body = Jason.decode!(resp.resp_body)
      assert body["error"]["code"] == "forbidden"
    end

    test "returns 401 without auth", %{conn: conn, merchant: merchant} do
      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/merchants/#{merchant.public_id}/keys", %{
          kind: "secret",
          mode: "simulation",
          scopes: []
        })

      assert resp.status == 401
    end

    test "returns 404 for unknown merchant", %{conn: conn, raw_key: raw_key} do
      resp =
        conn
        |> with_auth(raw_key)
        |> put_req_header("content-type", "application/json")
        |> post("/v1/merchants/mch_ghost/keys", %{
          kind: "secret",
          mode: "simulation",
          scopes: []
        })

      assert resp.status == 404
    end
  end

  describe "DELETE /v1/merchants/:merchant_id/keys/:id (revocation)" do
    test "revokes a key and returns it with revoked_at set", %{
      conn: conn,
      merchant: merchant,
      raw_key: raw_key
    } do
      {key_to_revoke, _} = Fixtures.api_key_fixture(merchant, %{mode: "simulation", scopes: []})

      resp =
        conn
        |> with_auth(raw_key)
        |> delete("/v1/merchants/#{merchant.public_id}/keys/#{key_to_revoke.public_id}")

      assert resp.status == 200
      body = Jason.decode!(resp.resp_body)
      assert body["object"] == "api_key"
      assert is_binary(body["revoked_at"])
    end

    test "returns 404 when key is already revoked", %{
      conn: conn,
      merchant: merchant,
      raw_key: raw_key
    } do
      {key_to_revoke, _} = Fixtures.api_key_fixture(merchant, %{mode: "simulation", scopes: []})

      # First revocation
      delete(
        with_auth(conn, raw_key),
        "/v1/merchants/#{merchant.public_id}/keys/#{key_to_revoke.public_id}"
      )

      # Second attempt
      resp =
        conn
        |> with_auth(raw_key)
        |> delete("/v1/merchants/#{merchant.public_id}/keys/#{key_to_revoke.public_id}")

      assert resp.status == 404
    end

    test "returns 401 without auth", %{conn: conn, merchant: merchant} do
      {key, _} = Fixtures.api_key_fixture(merchant, %{mode: "simulation", scopes: []})

      resp = delete(conn, "/v1/merchants/#{merchant.public_id}/keys/#{key.public_id}")
      assert resp.status == 401
    end
  end
end
