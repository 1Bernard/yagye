defmodule YagyeCoreWeb.Controllers.Webhooks.ProviderWebhookControllerTest do
  use YagyeCoreWeb.ConnCase, async: true

  import Ecto.Query

  alias YagyeCore.Fixtures
  alias YagyeCore.Repo
  alias YagyeCore.Webhooks.Schemas.WebhookEvent

  setup do
    {provider, secret} = Fixtures.webhook_provider_fixture()
    %{provider: provider, secret: secret}
  end

  defp signed_post(conn, provider_code, raw_body, secret, extra_headers \\ []) do
    hex = :crypto.mac(:hmac, :sha256, secret, raw_body) |> Base.encode16(case: :lower)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-webhook-signature", "sha256=#{hex}")

    conn = Enum.reduce(extra_headers, conn, fn {k, v}, c -> put_req_header(c, k, v) end)

    post(conn, "/provider-webhooks/#{provider_code}", raw_body)
  end

  defp event_body(overrides \\ %{}) do
    Map.merge(
      %{
        "event_id" => "evt_#{System.unique_integer([:positive])}",
        "event_type" => "charge.succeeded",
        "charge_ref" => "chg_001"
      },
      overrides
    )
    |> Jason.encode!()
  end

  describe "POST /provider-webhooks/:provider_code" do
    test "returns 200 with valid HMAC signature", %{
      conn: conn,
      provider: provider,
      secret: secret
    } do
      body = event_body()
      resp = signed_post(conn, provider.code, body, secret)
      assert resp.status == 200
    end

    test "inserts a webhook_events row on success", %{
      conn: conn,
      provider: provider,
      secret: secret
    } do
      event_id = "evt_#{System.unique_integer([:positive])}"
      body = event_body(%{"event_id" => event_id, "event_type" => "charge.succeeded"})

      signed_post(conn, provider.code, body, secret)

      assert Repo.get_by(WebhookEvent, provider_code: provider.code, event_id: event_id) != nil
    end

    test "returns 401 when HMAC signature is wrong", %{conn: conn, provider: provider} do
      body = event_body()
      resp = signed_post(conn, provider.code, body, "wrong_secret")
      assert resp.status == 401
    end

    test "returns 401 when x-webhook-signature header is missing", %{
      conn: conn,
      provider: provider
    } do
      body = event_body()

      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/provider-webhooks/#{provider.code}", body)

      assert resp.status == 401
    end

    test "returns 401 when signature is not in sha256= format", %{conn: conn, provider: provider} do
      body = event_body()

      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-webhook-signature", "md5=badhash")
        |> post("/provider-webhooks/#{provider.code}", body)

      assert resp.status == 401
    end

    test "returns 400 for an unknown provider code", %{conn: conn, secret: secret} do
      body = event_body()
      resp = signed_post(conn, "nonexistent_provider", body, secret)
      assert resp.status == 400
    end

    test "returns 422 when event_type is missing from body", %{
      conn: conn,
      provider: provider,
      secret: secret
    } do
      body = Jason.encode!(%{"event_id" => "evt_001", "charge_ref" => "chg_001"})
      resp = signed_post(conn, provider.code, body, secret)
      assert resp.status == 422
    end

    test "returns 422 when event_id is missing from body and header", %{
      conn: conn,
      provider: provider,
      secret: secret
    } do
      body = Jason.encode!(%{"event_type" => "charge.succeeded", "charge_ref" => "chg_001"})
      resp = signed_post(conn, provider.code, body, secret)
      assert resp.status == 422
    end

    test "returns 200 for a duplicate event (idempotent)", %{
      conn: conn,
      provider: provider,
      secret: secret
    } do
      event_id = "evt_dup_#{System.unique_integer([:positive])}"
      body = event_body(%{"event_id" => event_id})

      resp1 = signed_post(conn, provider.code, body, secret)
      assert resp1.status == 200

      resp2 = signed_post(conn, provider.code, body, secret)
      assert resp2.status == 200
    end

    test "duplicate does not insert a second webhook_events row", %{
      conn: conn,
      provider: provider,
      secret: secret
    } do
      event_id = "evt_dedup_#{System.unique_integer([:positive])}"
      body = event_body(%{"event_id" => event_id})

      signed_post(conn, provider.code, body, secret)
      signed_post(conn, provider.code, body, secret)

      count =
        Repo.aggregate(
          from(w in WebhookEvent,
            where: w.provider_code == ^provider.code and w.event_id == ^event_id
          ),
          :count
        )

      assert count == 1
    end

    test "event_id can be supplied via x-webhook-event-id header", %{
      conn: conn,
      provider: provider,
      secret: secret
    } do
      event_id = "evt_hdr_#{System.unique_integer([:positive])}"
      body = Jason.encode!(%{"event_type" => "charge.succeeded", "charge_ref" => "chg_001"})
      hex = :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)

      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-webhook-signature", "sha256=#{hex}")
        |> put_req_header("x-webhook-event-id", event_id)
        |> post("/provider-webhooks/#{provider.code}", body)

      assert resp.status == 200
      assert Repo.get_by(WebhookEvent, event_id: event_id) != nil
    end
  end
end
