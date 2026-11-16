defmodule YagyeCore.Payments.Adapters.StripeAdapterTest do
  use ExUnit.Case, async: true

  alias YagyeCore.Payments.Adapters.StripeAdapter
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}

  @credential %{
    "base_url" => "https://api.stripe.com/v1",
    "secret_key" => "sk_test_fake"
  }

  defp payment(method) do
    %Payment{
      id: Ecto.UUID.generate(),
      amount: 20_000,
      currency: "GHS",
      method: method,
      metadata: %{
        "msisdn" => "0241000001",
        "network" => "MTN",
        "email" => "customer@test.com"
      }
    }
  end

  defp attempt(token \\ nil) do
    token = token || "pi_test_#{System.unique_integer([:positive])}"

    %PaymentAttempt{
      id: Ecto.UUID.generate(),
      idempotency_token: token,
      provider_reference: token
    }
  end

  defp json_resp(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  # ── charge/3 — card ──────────────────────────────────────────────────────────

  describe "charge/3 — card" do
    test "succeeded PaymentIntent returns ok with provider_reference" do
      pi_id = "pi_test_abc123"

      Req.Test.stub(:stripe_http, fn conn ->
        Req.Test.json(conn, %{
          "id" => pi_id,
          "object" => "payment_intent",
          "status" => "succeeded",
          "latest_charge" => "ch_abc123"
        })
      end)

      p = %{
        payment("card")
        | metadata: Map.put(payment("card").metadata, "payment_method_id", "pm_card_visa")
      }

      assert {:ok, %{provider_reference: ^pi_id, auth_code: "ch_abc123"}} =
               StripeAdapter.charge(p, attempt(), @credential)
    end

    test "requires_payment_method returns pending" do
      pi_id = "pi_needs_pm"

      Req.Test.stub(:stripe_http, fn conn ->
        Req.Test.json(conn, %{
          "id" => pi_id,
          "object" => "payment_intent",
          "status" => "requires_payment_method"
        })
      end)

      assert {:pending, %{provider_reference: ^pi_id}} =
               StripeAdapter.charge(payment("card"), attempt(), @credential)
    end

    test "requires_action returns pending" do
      pi_id = "pi_needs_action"

      Req.Test.stub(:stripe_http, fn conn ->
        Req.Test.json(conn, %{"id" => pi_id, "status" => "requires_action"})
      end)

      assert {:pending, %{provider_reference: ^pi_id}} =
               StripeAdapter.charge(payment("card"), attempt(), @credential)
    end

    test "processing returns pending" do
      pi_id = "pi_processing"

      Req.Test.stub(:stripe_http, fn conn ->
        Req.Test.json(conn, %{"id" => pi_id, "status" => "processing"})
      end)

      assert {:pending, %{provider_reference: ^pi_id}} =
               StripeAdapter.charge(payment("card"), attempt(), @credential)
    end

    test "400 stripe error returns definite_failure" do
      Req.Test.stub(:stripe_http, fn conn ->
        json_resp(conn, 400, %{
          "error" => %{
            "type" => "invalid_request_error",
            "message" => "No such payment method"
          }
        })
      end)

      assert {:error,
              %{
                error_class: :definite_failure,
                response_code: "stripe_error",
                response_message: "No such payment method"
              }} =
               StripeAdapter.charge(payment("card"), attempt(), @credential)
    end

    test "402 card declined returns definite_failure" do
      Req.Test.stub(:stripe_http, fn conn ->
        json_resp(conn, 402, %{
          "error" => %{
            "type" => "card_error",
            "code" => "card_declined",
            "message" => "Your card was declined."
          }
        })
      end)

      assert {:error, %{error_class: :definite_failure, response_code: "stripe_error"}} =
               StripeAdapter.charge(payment("card"), attempt(), @credential)
    end

    test "5xx returns retryable_error" do
      Req.Test.stub(:stripe_http, fn conn ->
        Plug.Conn.send_resp(conn, 500, "")
      end)

      assert {:error, %{error_class: :retryable_error, response_code: "http_500"}} =
               StripeAdapter.charge(payment("card"), attempt(), @credential)
    end

    test "timeout returns indeterminate" do
      Req.Test.stub(:stripe_http, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, %{error_class: :indeterminate, response_code: "timeout"}} =
               StripeAdapter.charge(payment("card"), attempt(), @credential)
    end

    test "network error returns indeterminate" do
      Req.Test.stub(:stripe_http, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, %{error_class: :indeterminate, response_code: "network_error"}} =
               StripeAdapter.charge(payment("card"), attempt(), @credential)
    end

    test "sends amount in minor units (pesewas)" do
      Req.Test.stub(:stripe_http, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)
        assert params["amount"] == "20000"
        assert params["currency"] == "ghs"

        Req.Test.json(conn, %{
          "id" => "pi_check",
          "status" => "requires_payment_method"
        })
      end)

      StripeAdapter.charge(payment("card"), attempt(), @credential)
    end

    test "sends idempotency key header" do
      token = "idem_key_#{System.unique_integer([:positive])}"

      Req.Test.stub(:stripe_http, fn conn ->
        idem_header =
          conn.req_headers
          |> Enum.find(fn {k, _} -> k == "idempotency-key" end)
          |> elem(1)

        assert idem_header == token

        Req.Test.json(conn, %{"id" => "pi_x", "status" => "requires_payment_method"})
      end)

      StripeAdapter.charge(payment("card"), attempt(token), @credential)
    end

    test "unsupported method returns definite_failure" do
      assert {:error, %{error_class: :definite_failure, response_code: "method_not_supported"}} =
               StripeAdapter.charge(payment("bank_transfer"), attempt(), @credential)
    end
  end

  # ── charge/3 — mobile_money ──────────────────────────────────────────────────

  describe "charge/3 — mobile_money" do
    test "returns pending with provider_reference" do
      pi_id = "pi_momo_test"

      Req.Test.stub(:stripe_http, fn conn ->
        Req.Test.json(conn, %{"id" => pi_id, "status" => "requires_action"})
      end)

      assert {:pending, %{provider_reference: ^pi_id}} =
               StripeAdapter.charge(payment("mobile_money"), attempt(), @credential)
    end

    test "sends mobile_money payment method type" do
      Req.Test.stub(:stripe_http, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)
        assert params["payment_method_types[]"] == "mobile_money"
        assert params["payment_method_data[type]"] == "mobile_money"

        Req.Test.json(conn, %{"id" => "pi_momo_check", "status" => "processing"})
      end)

      StripeAdapter.charge(payment("mobile_money"), attempt(), @credential)
    end

    test "MTN maps to mtn network in metadata" do
      Req.Test.stub(:stripe_http, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)
        assert params["metadata[network]"] == "mtn"

        Req.Test.json(conn, %{"id" => "pi_mtn", "status" => "processing"})
      end)

      StripeAdapter.charge(payment("mobile_money"), attempt(), @credential)
    end

    test "Vodafone/Telecel maps to vodafone network" do
      for net <- ["Vodafone", "VODAFONE", "Telecel", "TELECEL"] do
        p = %{
          payment("mobile_money")
          | metadata: Map.put(payment("mobile_money").metadata, "network", net)
        }

        Req.Test.stub(:stripe_http, fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          params = URI.decode_query(body)
          assert params["metadata[network]"] == "vodafone"

          Req.Test.json(conn, %{"id" => "pi_vod", "status" => "processing"})
        end)

        assert {:pending, _} = StripeAdapter.charge(p, attempt(), @credential)
      end
    end

    test "AirtelTigo maps to airteltigo network" do
      for net <- ["AirtelTigo", "AIRTELTIGO", "airteltigo"] do
        p = %{
          payment("mobile_money")
          | metadata: Map.put(payment("mobile_money").metadata, "network", net)
        }

        Req.Test.stub(:stripe_http, fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          params = URI.decode_query(body)
          assert params["metadata[network]"] == "airteltigo"

          Req.Test.json(conn, %{"id" => "pi_at", "status" => "processing"})
        end)

        assert {:pending, _} = StripeAdapter.charge(p, attempt(), @credential)
      end
    end
  end

  # ── query_charge/2 ───────────────────────────────────────────────name──────────

  describe "query_charge/2" do
    defp attempt_with_ref(ref) do
      %PaymentAttempt{
        id: Ecto.UUID.generate(),
        idempotency_token: ref,
        provider_reference: ref
      }
    end

    test "succeeded returns ok with provider_reference and auth_code" do
      ref = "pi_query_test"

      Req.Test.stub(:stripe_http, fn conn ->
        assert String.contains?(conn.request_path, ref)

        Req.Test.json(conn, %{
          "id" => ref,
          "status" => "succeeded",
          "latest_charge" => "ch_xyz"
        })
      end)

      assert {:ok, %{provider_reference: ^ref, auth_code: "ch_xyz"}} =
               StripeAdapter.query_charge(attempt_with_ref(ref), @credential)
    end

    test "requires_action returns pending" do
      ref = "pi_needs_action"

      Req.Test.stub(:stripe_http, fn conn ->
        Req.Test.json(conn, %{"id" => ref, "status" => "requires_action"})
      end)

      assert {:pending, %{provider_reference: ^ref}} =
               StripeAdapter.query_charge(attempt_with_ref(ref), @credential)
    end

    test "canceled returns definite_failure" do
      Req.Test.stub(:stripe_http, fn conn ->
        Req.Test.json(conn, %{
          "id" => "pi_canceled",
          "status" => "canceled",
          "cancellation_reason" => "fraudulent"
        })
      end)

      assert {:error,
              %{
                error_class: :definite_failure,
                response_code: "canceled",
                response_message: "fraudulent"
              }} =
               StripeAdapter.query_charge(attempt_with_ref("pi_canceled"), @credential)
    end

    test "404 returns indeterminate / not_found" do
      Req.Test.stub(:stripe_http, fn conn ->
        Plug.Conn.send_resp(conn, 404, "")
      end)

      assert {:error, %{error_class: :indeterminate, response_code: "not_found"}} =
               StripeAdapter.query_charge(attempt_with_ref("pi_missing"), @credential)
    end

    test "5xx returns retryable_error" do
      Req.Test.stub(:stripe_http, fn conn ->
        Plug.Conn.send_resp(conn, 503, "")
      end)

      assert {:error, %{error_class: :retryable_error, response_code: "http_503"}} =
               StripeAdapter.query_charge(attempt_with_ref("pi_err"), @credential)
    end

    test "transport error returns indeterminate" do
      for reason <- [:timeout, :econnrefused] do
        Req.Test.stub(:stripe_http, fn conn ->
          Req.Test.transport_error(conn, reason)
        end)

        assert {:error, %{error_class: :indeterminate}} =
                 StripeAdapter.query_charge(attempt_with_ref("pi_net"), @credential)
      end
    end
  end

  # ── disburse/2 ───────────────────────────────────────────────────────────────

  describe "disburse/2" do
    @payout_params %{
      amount: 500_000,
      currency: "GHS",
      reference: "settle-ref-xyz"
    }

    test "successful payout returns pending with payout id" do
      Req.Test.stub(:stripe_http, fn conn ->
        Req.Test.json(conn, %{
          "id" => "po_abc123",
          "object" => "payout",
          "status" => "pending"
        })
      end)

      assert {:pending, %{provider_reference: "po_abc123"}} =
               StripeAdapter.disburse(@payout_params, @credential)
    end

    test "payout with status paid returns ok" do
      Req.Test.stub(:stripe_http, fn conn ->
        Req.Test.json(conn, %{"id" => "po_paid", "status" => "paid"})
      end)

      assert {:ok, %{provider_reference: "po_paid"}} =
               StripeAdapter.disburse(@payout_params, @credential)
    end

    test "stripe payout error returns definite_failure" do
      Req.Test.stub(:stripe_http, fn conn ->
        json_resp(conn, 400, %{
          "error" => %{
            "type" => "invalid_request_error",
            "message" => "You have insufficient funds in your Stripe account"
          }
        })
      end)

      assert {:error, %{error_class: :definite_failure, response_code: "payout_error"}} =
               StripeAdapter.disburse(@payout_params, @credential)
    end

    test "sends amount in minor units" do
      Req.Test.stub(:stripe_http, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)
        assert params["amount"] == "500000"
        assert params["currency"] == "ghs"

        Req.Test.json(conn, %{"id" => "po_check", "status" => "pending"})
      end)

      StripeAdapter.disburse(@payout_params, @credential)
    end

    test "missing params returns definite_failure / missing_params" do
      assert {:error, %{error_class: :definite_failure, response_code: "missing_params"}} =
               StripeAdapter.disburse(%{amount: 100}, @credential)
    end
  end
end
