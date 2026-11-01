defmodule YagyeCoreWeb.Controllers.Internal.EscrowControllerTest do
  use YagyeCoreWeb.ConnCase, async: true

  alias YagyeCore.Escrow.Schemas.EscrowHold
  alias YagyeCore.Fixtures
  alias YagyeCore.PaymentLinks.Schemas.PaymentLink
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}
  alias YagyeCore.Repo

  @portal_secret "test_portal_service_secret"

  defp internal_conn(conn) do
    conn
    |> put_req_header("x-service-name", "portal")
    |> put_req_header("x-service-token", @portal_secret)
    |> put_req_header("content-type", "application/json")
  end

  defp insert_payment_link(merchant, attrs \\ %{}) do
    %PaymentLink{}
    |> PaymentLink.changeset(
      Map.merge(
        %{
          merchant_id: merchant.id,
          mode: "simulation",
          url_slug: "link-#{System.unique_integer([:positive])}",
          kind: "fixed_amount",
          amount: 10_000,
          currency: "GHS",
          description: "Test",
          escrow_enabled: true,
          escrow_auto_release_days: 7,
          escrow_dispute_window_hours: 48
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp insert_escrow_hold(payment, link, attrs \\ %{}) do
    now = DateTime.utc_now()

    base = %{
      payment_id: payment.id,
      payment_link_id: link.id,
      merchant_id: payment.merchant_id,
      amount: payment.amount,
      currency: payment.currency,
      mode: payment.mode,
      auto_release_at: DateTime.add(now, 7 * 86_400, :second),
      dispute_window_ends_at: DateTime.add(now, 48 * 3600, :second)
    }

    cs = EscrowHold.changeset(%EscrowHold{}, base)

    cs =
      if state = Map.get(attrs, :state),
        do: Ecto.Changeset.put_change(cs, :state, state),
        else: cs

    Repo.insert!(cs)
  end

  defp insert_attempt(payment, provider) do
    Repo.insert!(
      PaymentAttempt.changeset(%PaymentAttempt{}, %{
        payment_id: payment.id,
        provider_id: provider.id,
        attempt_number: 1,
        state: "succeeded",
        provider_reference: "ref_#{System.unique_integer([:positive])}",
        idempotency_token: Uniq.UUID.uuid7()
      })
    )
  end

  # ── GET /internal/escrow/holds/:public_id ────────────────────────────────────

  describe "GET /internal/escrow/holds/:public_id" do
    test "returns 200 with hold", %{conn: conn} do
      merchant = Fixtures.merchant_fixture()
      payment = Fixtures.payment_fixture(merchant)
      link = insert_payment_link(merchant)
      hold = insert_escrow_hold(payment, link)

      resp = conn |> internal_conn() |> get("/internal/escrow/holds/#{hold.public_id}")

      assert resp.status == 200
      body = Jason.decode!(resp.resp_body)
      assert body["public_id"] == hold.public_id
    end

    test "returns 404 for unknown public_id", %{conn: conn} do
      resp = conn |> internal_conn() |> get("/internal/escrow/holds/esh_notreal")
      assert resp.status == 404
    end

    test "returns 401 without service token", %{conn: conn} do
      resp = get(conn, "/internal/escrow/holds/esh_test")
      assert resp.status == 401
    end
  end

  # ── GET /internal/escrow/holds ───────────────────────────────────────────────

  describe "GET /internal/escrow/holds" do
    test "returns holds for merchant_id", %{conn: conn} do
      merchant = Fixtures.merchant_fixture()
      payment = Fixtures.payment_fixture(merchant)
      link = insert_payment_link(merchant)
      _hold = insert_escrow_hold(payment, link)

      resp =
        conn
        |> internal_conn()
        |> get("/internal/escrow/holds?merchant_id=#{merchant.id}")

      assert resp.status == 200
      body = Jason.decode!(resp.resp_body)
      assert is_list(body)
      assert length(body) == 1
    end

    test "filters by state", %{conn: conn} do
      merchant = Fixtures.merchant_fixture()
      payment_a = Fixtures.payment_fixture(merchant)
      payment_b = Fixtures.payment_fixture(merchant)
      link = insert_payment_link(merchant)

      insert_escrow_hold(payment_a, link)
      insert_escrow_hold(payment_b, link, %{state: "released"})

      resp =
        conn
        |> internal_conn()
        |> get("/internal/escrow/holds?merchant_id=#{merchant.id}&state=held")

      assert resp.status == 200
      body = Jason.decode!(resp.resp_body)
      assert length(body) == 1
    end
  end

  # ── POST /internal/escrow/holds/:public_id/open-dispute ──────────────────────

  describe "POST /internal/escrow/holds/:public_id/open-dispute" do
    test "returns 200 with disputed hold", %{conn: conn} do
      merchant = Fixtures.merchant_fixture()
      payment = Fixtures.payment_fixture(merchant)
      {:ok, payment} = payment |> Payment.transition_changeset("escrow_held") |> Repo.update()

      link = insert_payment_link(merchant)
      hold = insert_escrow_hold(payment, link)

      resp =
        conn
        |> internal_conn()
        |> post(
          "/internal/escrow/holds/#{hold.public_id}/open-dispute",
          Jason.encode!(%{actor: "buyer", note: "Item not received"})
        )

      assert resp.status == 200
      body = Jason.decode!(resp.resp_body)
      assert body["state"] == "disputed"
    end

    test "returns 422 for non-held hold", %{conn: conn} do
      merchant = Fixtures.merchant_fixture()
      payment = Fixtures.payment_fixture(merchant)
      {:ok, payment} = payment |> Payment.transition_changeset("escrow_disputed") |> Repo.update()

      link = insert_payment_link(merchant)
      hold = insert_escrow_hold(payment, link, %{state: "disputed"})

      resp =
        conn
        |> internal_conn()
        |> post(
          "/internal/escrow/holds/#{hold.public_id}/open-dispute",
          Jason.encode!(%{actor: "buyer", note: "again"})
        )

      assert resp.status == 422
    end
  end

  # ── POST /internal/escrow/holds/:public_id/confirm-release ───────────────────

  describe "POST /internal/escrow/holds/:public_id/confirm-release" do
    test "returns 200 with released hold", %{conn: conn} do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.provider_fixture()
      payment = Fixtures.payment_fixture(merchant)
      {:ok, payment} = payment |> Payment.transition_changeset("escrow_held") |> Repo.update()

      attempt = insert_attempt(payment, provider)
      link = insert_payment_link(merchant)
      hold = insert_escrow_hold(payment, link)

      resp =
        conn
        |> internal_conn()
        |> post(
          "/internal/escrow/holds/#{hold.public_id}/confirm-release",
          Jason.encode!(%{attempt_id: attempt.id})
        )

      assert resp.status == 200
      body = Jason.decode!(resp.resp_body)
      assert body["state"] == "released"
    end
  end
end
