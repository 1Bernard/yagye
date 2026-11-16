defmodule YagyeCore.Payments.Adapters.FlutterwaveAdapterTest do
  use ExUnit.Case, async: true

  alias YagyeCore.Payments.Adapters.FlutterwaveAdapter
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}

  @credential %{
    "base_url" => "http://flw-test.local/v3",
    "secret_key" => "FLWSECK_TEST-fake-key",
    "webhook_hash" => "test-hash"
  }

  defp payment(method \\ "mobile_money") do
    %Payment{
      id: Ecto.UUID.generate(),
      amount: 10_000,
      currency: "GHS",
      method: method,
      metadata: %{
        "msisdn" => "0244000001",
        "network" => "MTN",
        "email" => "customer@test.com",
        "account_name" => "Test Customer"
      }
    }
  end

  defp attempt do
    %PaymentAttempt{
      id: Ecto.UUID.generate(),
      idempotency_token: "tx_ref_#{System.unique_integer([:positive])}",
      provider_reference: nil
    }
  end

  defp json_resp(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  # ── charge/3 ─────────────────────────────────────────────────────────────────

  describe "charge/3" do
    test "200 success with pending data returns pending with provider_reference" do
      flw_id = 987_654

      Req.Test.stub(:flutterwave_http, fn conn ->
        Req.Test.json(conn, %{
          "status" => "success",
          "data" => %{
            "id" => flw_id,
            "status" => "pending",
            "tx_ref" => "some-tx-ref"
          }
        })
      end)

      assert {:pending, %{provider_reference: ref}} =
               FlutterwaveAdapter.charge(payment(), attempt(), @credential)

      assert ref == to_string(flw_id)
    end

    test "200 with data.status=successful returns ok immediately" do
      flw_id = 123_456

      Req.Test.stub(:flutterwave_http, fn conn ->
        Req.Test.json(conn, %{
          "status" => "success",
          "data" => %{
            "id" => flw_id,
            "status" => "successful",
            "flw_ref" => "FLW-REF-abc"
          }
        })
      end)

      assert {:ok, %{provider_reference: ref, auth_code: "FLW-REF-abc"}} =
               FlutterwaveAdapter.charge(payment(), attempt(), @credential)

      assert ref == to_string(flw_id)
    end

    test "200 with status=error in body returns definite_failure" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        Req.Test.json(conn, %{
          "status" => "error",
          "message" => "Invalid phone number"
        })
      end)

      assert {:error,
              %{
                error_class: :definite_failure,
                response_code: "flw_error",
                response_message: "Invalid phone number"
              }} = FlutterwaveAdapter.charge(payment(), attempt(), @credential)
    end

    test "400 returns definite_failure / invalid_request" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        json_resp(conn, 400, %{"message" => "Bad request"})
      end)

      assert {:error, %{error_class: :definite_failure, response_code: "invalid_request"}} =
               FlutterwaveAdapter.charge(payment(), attempt(), @credential)
    end

    test "5xx returns retryable_error" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        Plug.Conn.send_resp(conn, 502, "")
      end)

      assert {:error, %{error_class: :retryable_error, response_code: "http_502"}} =
               FlutterwaveAdapter.charge(payment(), attempt(), @credential)
    end

    test "non-mobile_money method returns definite_failure / method_not_supported" do
      assert {:error, %{error_class: :definite_failure, response_code: "method_not_supported"}} =
               FlutterwaveAdapter.charge(payment("card"), attempt(), @credential)
    end

    test "amount is sent as major units (cedis, not pesewas)" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        # 10_000 pesewas = 100.0 cedis
        assert decoded["amount"] == 100.0

        Req.Test.json(conn, %{
          "status" => "success",
          "data" => %{"id" => 1, "status" => "pending"}
        })
      end)

      FlutterwaveAdapter.charge(payment(), attempt(), @credential)
    end

    test "MTN network maps to FLW code MTN" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["network"] == "MTN"

        Req.Test.json(conn, %{
          "status" => "success",
          "data" => %{"id" => 1, "status" => "pending"}
        })
      end)

      FlutterwaveAdapter.charge(payment(), attempt(), @credential)
    end

    test "Vodafone network maps to VDF" do
      p = %{payment() | metadata: Map.put(payment().metadata, "network", "Vodafone")}

      Req.Test.stub(:flutterwave_http, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["network"] == "VDF"

        Req.Test.json(conn, %{
          "status" => "success",
          "data" => %{"id" => 1, "status" => "pending"}
        })
      end)

      FlutterwaveAdapter.charge(p, attempt(), @credential)
    end

    test "Telecel network maps to VDF" do
      for net <- ["Telecel", "TELECEL", "telecel"] do
        p = %{payment() | metadata: Map.put(payment().metadata, "network", net)}

        Req.Test.stub(:flutterwave_http, fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          assert Jason.decode!(body)["network"] == "VDF"

          Req.Test.json(conn, %{
            "status" => "success",
            "data" => %{"id" => 1, "status" => "pending"}
          })
        end)

        assert {:pending, %{provider_reference: "1"}} =
                 FlutterwaveAdapter.charge(p, attempt(), @credential)
      end
    end

    test "AirtelTigo network maps to ATL" do
      for net <- ["AirtelTigo", "AIRTELTIGO", "airteltigo"] do
        p = %{payment() | metadata: Map.put(payment().metadata, "network", net)}

        Req.Test.stub(:flutterwave_http, fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          assert Jason.decode!(body)["network"] == "ATL"

          Req.Test.json(conn, %{
            "status" => "success",
            "data" => %{"id" => 2, "status" => "pending"}
          })
        end)

        assert {:pending, %{provider_reference: "2"}} =
                 FlutterwaveAdapter.charge(p, attempt(), @credential)
      end
    end

    test "timeout returns indeterminate / timeout" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, %{error_class: :indeterminate, response_code: "timeout"}} =
               FlutterwaveAdapter.charge(payment(), attempt(), @credential)
    end

    test "network error returns indeterminate / network_error" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, %{error_class: :indeterminate, response_code: "network_error"}} =
               FlutterwaveAdapter.charge(payment(), attempt(), @credential)
    end
  end

  # ── query_charge/2 ───────────────────────────────────────────────────────────

  describe "query_charge/2" do
    defp attempt_with_ref(ref) do
      %PaymentAttempt{
        id: Ecto.UUID.generate(),
        idempotency_token: Ecto.UUID.generate(),
        provider_reference: ref
      }
    end

    test "200 successful data returns ok" do
      flw_id = 555

      Req.Test.stub(:flutterwave_http, fn conn ->
        assert String.contains?(conn.request_path, to_string(flw_id))

        Req.Test.json(conn, %{
          "status" => "success",
          "data" => %{
            "status" => "successful",
            "id" => flw_id,
            "flw_ref" => "FLW-REF-xyz"
          }
        })
      end)

      assert {:ok, %{provider_reference: ref, auth_code: "FLW-REF-xyz"}} =
               FlutterwaveAdapter.query_charge(attempt_with_ref(to_string(flw_id)), @credential)

      assert ref == to_string(flw_id)
    end

    test "200 failed data returns definite_failure" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        Req.Test.json(conn, %{
          "status" => "success",
          "data" => %{
            "status" => "failed",
            "processor_response" => "Customer cancelled"
          }
        })
      end)

      assert {:error,
              %{
                error_class: :definite_failure,
                response_code: "flw_failed",
                response_message: "Customer cancelled"
              }} = FlutterwaveAdapter.query_charge(attempt_with_ref("99"), @credential)
    end

    test "404 returns indeterminate / not_found" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        Plug.Conn.send_resp(conn, 404, "")
      end)

      assert {:error, %{error_class: :indeterminate, response_code: "not_found"}} =
               FlutterwaveAdapter.query_charge(attempt_with_ref("missing"), @credential)
    end

    test "non-200/404 returns retryable_error" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        Plug.Conn.send_resp(conn, 503, "")
      end)

      assert {:error, %{error_class: :retryable_error, response_code: "http_503"}} =
               FlutterwaveAdapter.query_charge(attempt_with_ref("ref-123"), @credential)
    end

    test "pending status on verify returns retryable_error" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        Req.Test.json(conn, %{
          "status" => "success",
          "data" => %{"status" => "pending"}
        })
      end)

      assert {:error, %{error_class: :retryable_error, response_code: "flw_pending"}} =
               FlutterwaveAdapter.query_charge(attempt_with_ref("ref-pend"), @credential)
    end

    test "transport error (timeout or refused) returns indeterminate / network_error" do
      for reason <- [:timeout, :econnrefused] do
        Req.Test.stub(:flutterwave_http, fn conn ->
          Req.Test.transport_error(conn, reason)
        end)

        assert {:error, %{error_class: :indeterminate, response_code: "network_error"}} =
                 FlutterwaveAdapter.query_charge(attempt_with_ref("ref-net"), @credential)
      end
    end
  end

  # ── disburse/2 ──────────────────────────────────────────────────────────────

  describe "disburse/2" do
    @momo_params %{
      amount: 20_000,
      currency: "GHS",
      reference: "payout-momo-001",
      recipient_msisdn: "0241000001",
      recipient_name: "Ama Owusu"
    }

    @bank_params %{
      amount: 500_000,
      currency: "GHS",
      reference: "payout-bank-002",
      recipient_bank_code: "GH290101",
      recipient_account_number: "9876543210",
      recipient_name: "Kofi Ltd"
    }

    test "mobile money payout returns pending with provider_reference" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        Req.Test.json(conn, %{
          "status" => "success",
          "data" => %{"id" => 4001, "transfer_code" => "FLW-TRF-momo"}
        })
      end)

      assert {:pending, %{provider_reference: "FLW-TRF-momo"}} =
               FlutterwaveAdapter.disburse(@momo_params, @credential)
    end

    test "bank transfer payout returns pending with provider_reference" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        Req.Test.json(conn, %{
          "status" => "success",
          "data" => %{"id" => 4002, "transfer_code" => "FLW-TRF-bank"}
        })
      end)

      assert {:pending, %{provider_reference: "FLW-TRF-bank"}} =
               FlutterwaveAdapter.disburse(@bank_params, @credential)
    end

    test "MoMo amount is converted to major units (cedis)" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        # 20_000 pesewas = 200.0 cedis
        assert decoded["amount"] == 200.0

        Req.Test.json(conn, %{
          "status" => "success",
          "data" => %{"id" => 1, "transfer_code" => "FLW-TRF-unit"}
        })
      end)

      FlutterwaveAdapter.disburse(@momo_params, @credential)
    end

    test "MoMo payout body includes mobile_number and type=mobile_money_gh" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["type"] == "mobile_money_gh"
        assert decoded["mobile_number"] == "0241000001"
        assert decoded["beneficiary_name"] == "Ama Owusu"
        assert decoded["reference"] == "payout-momo-001"

        Req.Test.json(conn, %{
          "status" => "success",
          "data" => %{"id" => 1, "transfer_code" => "FLW-TRF-body"}
        })
      end)

      FlutterwaveAdapter.disburse(@momo_params, @credential)
    end

    test "bank transfer body uses bank_code as type and includes account_number" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["type"] == "GH290101"
        assert decoded["account_number"] == "9876543210"
        assert decoded["beneficiary_name"] == "Kofi Ltd"

        Req.Test.json(conn, %{
          "status" => "success",
          "data" => %{"id" => 2, "transfer_code" => "FLW-TRF-bank-body"}
        })
      end)

      FlutterwaveAdapter.disburse(@bank_params, @credential)
    end

    test "error body returns definite_failure" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        Req.Test.json(conn, %{
          "status" => "error",
          "message" => "Invalid mobile number"
        })
      end)

      assert {:error,
              %{
                error_class: :definite_failure,
                response_code: "flw_error",
                response_message: "Invalid mobile number"
              }} = FlutterwaveAdapter.disburse(@momo_params, @credential)
    end

    test "400 returns definite_failure / invalid_request" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, Jason.encode!(%{"message" => "Bad request"}))
      end)

      assert {:error, %{error_class: :definite_failure, response_code: "invalid_request"}} =
               FlutterwaveAdapter.disburse(@momo_params, @credential)
    end

    test "5xx returns retryable_error" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        Plug.Conn.send_resp(conn, 502, "")
      end)

      assert {:error, %{error_class: :retryable_error, response_code: "http_502"}} =
               FlutterwaveAdapter.disburse(@momo_params, @credential)
    end

    test "timeout returns indeterminate / timeout" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, %{error_class: :indeterminate, response_code: "timeout"}} =
               FlutterwaveAdapter.disburse(@momo_params, @credential)
    end

    test "network error returns indeterminate / network_error" do
      Req.Test.stub(:flutterwave_http, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, %{error_class: :indeterminate, response_code: "network_error"}} =
               FlutterwaveAdapter.disburse(@momo_params, @credential)
    end

    test "missing params returns definite_failure / missing_params" do
      assert {:error, %{error_class: :definite_failure, response_code: "missing_params"}} =
               FlutterwaveAdapter.disburse(
                 %{amount: 100, currency: "GHS", reference: "ref"},
                 @credential
               )
    end
  end
end
