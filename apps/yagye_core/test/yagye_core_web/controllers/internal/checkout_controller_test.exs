defmodule YagyeCoreWeb.Controllers.Internal.CheckoutControllerTest do
  use YagyeCoreWeb.ConnCase, async: true

  alias YagyeCore.CheckoutSessions
  alias YagyeCore.Fixtures
  alias YagyeCore.PaymentLinks.Schemas.PaymentLink
  alias YagyeCore.Payments
  alias YagyeCore.Repo

  @portal_secret "test_portal_service_secret"

  defp internal_conn(conn) do
    conn
    |> put_req_header("x-service-name", "portal")
    |> put_req_header("x-service-token", @portal_secret)
    |> put_req_header("content-type", "application/json")
  end

  defp insert_payment_link(merchant, attrs) do
    %PaymentLink{}
    |> PaymentLink.changeset(
      Map.merge(
        %{
          merchant_id: merchant.id,
          mode: "simulation",
          url_slug: "link-#{System.unique_integer([:positive])}",
          kind: "fixed_amount",
          amount: 15_000,
          currency: "GHS",
          description: "Checkout Test Link"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  describe "POST /internal/checkout/sessions/:public_id/pay (PCI-DSS PAN redaction)" do
    test "stores only card_last4 and never persists raw card_number in payment.metadata", %{
      conn: conn
    } do
      merchant = Fixtures.merchant_fixture()

      {:ok, {session, _token}} =
        CheckoutSessions.create_session(merchant.id, %{
          mode: "simulation",
          subtotal_amount: 15_000,
          total_amount: 15_000,
          currency: "GHS",
          description: "Card Checkout",
          success_url: "https://merchant.example.com/success",
          cancel_url: "https://merchant.example.com/cancel"
        })

      conn =
        conn
        |> internal_conn()
        |> post("/internal/checkout/sessions/#{session.public_id}/pay", %{
          "method" => "card",
          "card_number" => "4242 4242 4242 4242",
          "customer_email" => "buyer@example.com",
          "submission_token" => "tok_pci_test_1"
        })

      assert %{"payment_public_id" => payment_pub_id, "session_state" => "processing"} =
               json_response(conn, 200)

      assert {:ok, payment} = Payments.get_payment(payment_pub_id)
      assert payment.metadata["card_last4"] == "4242"
      refute Map.has_key?(payment.metadata, "card_number")
    end
  end

  describe "POST /internal/checkout/sessions/from-link (reusable and max_uses enforcement)" do
    test "rejects single-use payment link (reusable: false) when use_count >= 1", %{conn: conn} do
      merchant = Fixtures.merchant_fixture()
      link = insert_payment_link(merchant, %{reusable: false, use_count: 1})

      conn =
        conn
        |> internal_conn()
        |> post("/internal/checkout/sessions/from-link", %{"slug" => link.url_slug})

      assert %{"error" => "link_inactive"} = json_response(conn, 404)
    end

    test "rejects payment link when use_count >= max_uses", %{conn: conn} do
      merchant = Fixtures.merchant_fixture()
      link = insert_payment_link(merchant, %{reusable: true, max_uses: 3, use_count: 3})

      conn =
        conn
        |> internal_conn()
        |> post("/internal/checkout/sessions/from-link", %{"slug" => link.url_slug})

      assert %{"error" => "link_inactive"} = json_response(conn, 404)
    end

    test "allows reusable payment link below max_uses", %{conn: conn} do
      merchant = Fixtures.merchant_fixture()
      link = insert_payment_link(merchant, %{reusable: true, max_uses: 3, use_count: 2})

      conn =
        conn
        |> internal_conn()
        |> post("/internal/checkout/sessions/from-link", %{"slug" => link.url_slug})

      assert %{"token" => token} = json_response(conn, 200)
      assert is_binary(token)
    end
  end
end
