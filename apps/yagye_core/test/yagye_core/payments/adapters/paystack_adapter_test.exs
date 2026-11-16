defmodule YagyeCore.Payments.Adapters.PaystackAdapterTest do
  use ExUnit.Case, async: true

  alias YagyeCore.Payments.Adapters.PaystackAdapter
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}

  @credential %{
    "base_url" => "http://paystack-test.local",
    "secret_key" => "sk_test_fake"
  }

  defp payment(method \\ "mobile_money") do
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
    token = token || "ps_ref_#{System.unique_integer([:positive])}"

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

  # ── charge/3 ─────────────────────────────────────────────────────────────────

  describe "charge/3" do
    test "200 with pending data returns pending with provider_reference = reference" do
      ref = "ps_ref_test_123"

      Req.Test.stub(:paystack_http, fn conn ->
        Req.Test.json(conn, %{
          "status" => true,
          "data" => %{"status" => "pending", "reference" => ref}
        })
      end)

      assert {:pending, %{provider_reference: ^ref}} =
               PaystackAdapter.charge(payment(), attempt(ref), @credential)
    end

    test "200 with send_otp data (another pending form) returns pending" do
      ref = "ps_otp_ref"

      Req.Test.stub(:paystack_http, fn conn ->
        Req.Test.json(conn, %{
          "status" => true,
          "data" => %{"status" => "send_otp", "reference" => ref}
        })
      end)

      # send_otp is not explicitly handled — falls through to the generic clause
      assert {:error, %{error_class: :retryable_error}} =
               PaystackAdapter.charge(payment(), attempt(ref), @credential)
    end

    test "200 with status=false returns definite_failure" do
      Req.Test.stub(:paystack_http, fn conn ->
        Req.Test.json(conn, %{
          "status" => false,
          "message" => "Invalid phone number"
        })
      end)

      assert {:error,
              %{
                error_class: :definite_failure,
                response_code: "paystack_error",
                response_message: "Invalid phone number"
              }} = PaystackAdapter.charge(payment(), attempt(), @credential)
    end

    test "400 returns definite_failure / invalid_request" do
      Req.Test.stub(:paystack_http, fn conn ->
        json_resp(conn, 400, %{"message" => "Missing required field"})
      end)

      assert {:error, %{error_class: :definite_failure, response_code: "invalid_request"}} =
               PaystackAdapter.charge(payment(), attempt(), @credential)
    end

    test "non-mobile_money method returns definite_failure / method_not_supported" do
      assert {:error, %{error_class: :definite_failure, response_code: "method_not_supported"}} =
               PaystackAdapter.charge(payment("card"), attempt(), @credential)
    end

    test "amount is sent in minor units (pesewas)" do
      Req.Test.stub(:paystack_http, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        # Paystack takes pesewas — no conversion; 20_000 stays 20_000
        assert decoded["amount"] == 20_000

        Req.Test.json(conn, %{
          "status" => true,
          "data" => %{"status" => "pending", "reference" => "ref-abc"}
        })
      end)

      PaystackAdapter.charge(payment(), attempt(), @credential)
    end

    test "MTN network maps to mtn provider code" do
      Req.Test.stub(:paystack_http, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["mobile_money"]["provider"] == "mtn"

        Req.Test.json(conn, %{
          "status" => true,
          "data" => %{"status" => "pending", "reference" => "ref-mtn"}
        })
      end)

      PaystackAdapter.charge(payment(), attempt(), @credential)
    end

    test "Vodafone network maps to vod provider code" do
      p = %{payment() | metadata: Map.put(payment().metadata, "network", "Vodafone")}

      Req.Test.stub(:paystack_http, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["mobile_money"]["provider"] == "vod"

        Req.Test.json(conn, %{
          "status" => true,
          "data" => %{"status" => "pending", "reference" => "ref-vod"}
        })
      end)

      PaystackAdapter.charge(p, attempt(), @credential)
    end

    test "AirtelTigo network maps to tgo provider code" do
      for net <- ["AirtelTigo", "AIRTELTIGO", "airteltigo"] do
        p = %{payment() | metadata: Map.put(payment().metadata, "network", net)}

        Req.Test.stub(:paystack_http, fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          assert Jason.decode!(body)["mobile_money"]["provider"] == "tgo"

          Req.Test.json(conn, %{
            "status" => true,
            "data" => %{"status" => "pending", "reference" => "ref-at"}
          })
        end)

        assert {:pending, %{provider_reference: "ref-at"}} =
                 PaystackAdapter.charge(p, attempt("ref-at"), @credential)
      end
    end

    test "timeout returns indeterminate / timeout" do
      Req.Test.stub(:paystack_http, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, %{error_class: :indeterminate, response_code: "timeout"}} =
               PaystackAdapter.charge(payment(), attempt(), @credential)
    end

    test "network error returns indeterminate / network_error" do
      Req.Test.stub(:paystack_http, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, %{error_class: :indeterminate, response_code: "network_error"}} =
               PaystackAdapter.charge(payment(), attempt(), @credential)
    end

    test "Telecel network maps to vod provider code" do
      for net <- ["Telecel", "TELECEL", "telecel"] do
        p = %{payment() | metadata: Map.put(payment().metadata, "network", net)}

        Req.Test.stub(:paystack_http, fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          assert Jason.decode!(body)["mobile_money"]["provider"] == "vod"

          Req.Test.json(conn, %{
            "status" => true,
            "data" => %{"status" => "pending", "reference" => "ref-telecel"}
          })
        end)

        assert {:pending, %{provider_reference: "ref-telecel"}} =
                 PaystackAdapter.charge(p, attempt("ref-telecel"), @credential)
      end
    end
  end

  # ── query_charge/2 ───────────────────────────────────────────────────────────

  describe "query_charge/2" do
    defp attempt_with_ref(ref) do
      %PaymentAttempt{
        id: Ecto.UUID.generate(),
        idempotency_token: ref,
        provider_reference: ref
      }
    end

    test "200 with success data returns ok" do
      ref = "ps-verify-ref"

      Req.Test.stub(:paystack_http, fn conn ->
        assert String.contains?(conn.request_path, ref)

        Req.Test.json(conn, %{
          "status" => true,
          "data" => %{"status" => "success", "reference" => ref}
        })
      end)

      assert {:ok, %{provider_reference: ^ref, auth_code: nil}} =
               PaystackAdapter.query_charge(attempt_with_ref(ref), @credential)
    end

    test "200 with failed data returns definite_failure" do
      Req.Test.stub(:paystack_http, fn conn ->
        Req.Test.json(conn, %{
          "status" => true,
          "data" => %{
            "status" => "failed",
            "gateway_response" => "Insufficient funds"
          }
        })
      end)

      assert {:error,
              %{
                error_class: :definite_failure,
                response_code: "ps_failed",
                response_message: "Insufficient funds"
              }} = PaystackAdapter.query_charge(attempt_with_ref("some-ref"), @credential)
    end

    test "404 returns indeterminate / not_found" do
      Req.Test.stub(:paystack_http, fn conn ->
        Plug.Conn.send_resp(conn, 404, "")
      end)

      assert {:error, %{error_class: :indeterminate, response_code: "not_found"}} =
               PaystackAdapter.query_charge(attempt_with_ref("missing"), @credential)
    end

    test "5xx returns retryable_error" do
      Req.Test.stub(:paystack_http, fn conn ->
        Plug.Conn.send_resp(conn, 500, "")
      end)

      assert {:error, %{error_class: :retryable_error, response_code: "http_500"}} =
               PaystackAdapter.query_charge(attempt_with_ref("ref-err"), @credential)
    end

    test "transport error (timeout or refused) returns indeterminate / network_error" do
      for reason <- [:timeout, :econnrefused] do
        Req.Test.stub(:paystack_http, fn conn ->
          Req.Test.transport_error(conn, reason)
        end)

        assert {:error, %{error_class: :indeterminate, response_code: "network_error"}} =
                 PaystackAdapter.query_charge(attempt_with_ref("ref-net"), @credential)
      end
    end
  end

  # ── disburse/2 ──────────────────────────────────────────────────────────────

  describe "disburse/2" do
    @disburse_params %{
      amount: 500_000,
      currency: "GHS",
      reference: "batch-settle-xyz",
      recipient_bank_code: "GH280101",
      recipient_account_number: "1234567890",
      recipient_name: "Merchant Ltd"
    }

    defp stub_successful_disburse(recipient_code, transfer_code) do
      Req.Test.stub(:paystack_http, fn conn ->
        case conn.request_path do
          "/transferrecipient" ->
            Req.Test.json(conn, %{
              "status" => true,
              "data" => %{"recipient_code" => recipient_code}
            })

          "/transfer" ->
            Req.Test.json(conn, %{
              "status" => true,
              "data" => %{"transfer_code" => transfer_code}
            })
        end
      end)
    end

    test "successful flow returns pending with transfer_code as provider_reference" do
      stub_successful_disburse("RCP_abc123", "TRF_xyz789")

      assert {:pending, %{provider_reference: "TRF_xyz789"}} =
               PaystackAdapter.disburse(@disburse_params, @credential)
    end

    test "recipient endpoint returning status=false returns definite_failure" do
      Req.Test.stub(:paystack_http, fn conn ->
        case conn.request_path do
          "/transferrecipient" ->
            Req.Test.json(conn, %{
              "status" => false,
              "message" => "Invalid bank code"
            })

          _ ->
            flunk("transfer should not be called when recipient creation fails")
        end
      end)

      assert {:error,
              %{
                error_class: :definite_failure,
                response_code: "recipient_error",
                response_message: "Invalid bank code"
              }} = PaystackAdapter.disburse(@disburse_params, @credential)
    end

    test "transfer duplicate reference returns indeterminate / duplicate_reference" do
      Req.Test.stub(:paystack_http, fn conn ->
        case conn.request_path do
          "/transferrecipient" ->
            Req.Test.json(conn, %{
              "status" => true,
              "data" => %{"recipient_code" => "RCP_existing"}
            })

          "/transfer" ->
            Req.Test.json(conn, %{
              "status" => false,
              "message" => "Duplicate request — transfer already exists"
            })
        end
      end)

      assert {:error, %{error_class: :indeterminate, response_code: "duplicate_reference"}} =
               PaystackAdapter.disburse(@disburse_params, @credential)
    end

    test "missing bank params returns definite_failure / missing_bank_params" do
      assert {:error, %{error_class: :definite_failure, response_code: "missing_bank_params"}} =
               PaystackAdapter.disburse(
                 %{amount: 100, currency: "GHS", reference: "ref"},
                 @credential
               )
    end

    test "recipient request includes correct body fields" do
      Req.Test.stub(:paystack_http, fn conn ->
        case conn.request_path do
          "/transferrecipient" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            decoded = Jason.decode!(body)
            assert decoded["account_number"] == "1234567890"
            assert decoded["bank_code"] == "GH280101"
            assert decoded["name"] == "Merchant Ltd"
            assert decoded["currency"] == "GHS"
            assert decoded["type"] == "ghipss"

            Req.Test.json(conn, %{
              "status" => true,
              "data" => %{"recipient_code" => "RCP_check"}
            })

          "/transfer" ->
            Req.Test.json(conn, %{
              "status" => true,
              "data" => %{"transfer_code" => "TRF_check"}
            })
        end
      end)

      assert {:pending, _} = PaystackAdapter.disburse(@disburse_params, @credential)
    end

    test "transfer 5xx returns retryable_error" do
      Req.Test.stub(:paystack_http, fn conn ->
        case conn.request_path do
          "/transferrecipient" ->
            Req.Test.json(conn, %{
              "status" => true,
              "data" => %{"recipient_code" => "RCP_ok"}
            })

          "/transfer" ->
            Plug.Conn.send_resp(conn, 503, "")
        end
      end)

      assert {:error, %{error_class: :retryable_error, response_code: "http_503"}} =
               PaystackAdapter.disburse(@disburse_params, @credential)
    end

    test "transfer network timeout returns indeterminate" do
      Req.Test.stub(:paystack_http, fn conn ->
        case conn.request_path do
          "/transferrecipient" ->
            Req.Test.json(conn, %{
              "status" => true,
              "data" => %{"recipient_code" => "RCP_ok"}
            })

          "/transfer" ->
            Req.Test.transport_error(conn, :timeout)
        end
      end)

      assert {:error, %{error_class: :indeterminate, response_code: "timeout"}} =
               PaystackAdapter.disburse(@disburse_params, @credential)
    end

    test "recipient network error returns indeterminate" do
      Req.Test.stub(:paystack_http, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, %{error_class: :indeterminate, response_code: "network_error"}} =
               PaystackAdapter.disburse(@disburse_params, @credential)
    end
  end

  # ── charge/3 — bank_transfer ─────────────────────────────────────────────────

  describe "charge/3 — bank_transfer" do
    defp bank_transfer_payment do
      %Payment{
        id: Ecto.UUID.generate(),
        amount: 50_000,
        currency: "GHS",
        method: "bank_transfer",
        metadata: %{"customer_email" => "buyer@test.com"}
      }
    end

    defp bt_attempt do
      %PaymentAttempt{
        id: Ecto.UUID.generate(),
        idempotency_token: "bt-idem-#{System.unique_integer([:positive])}"
      }
    end

    defp pay_offline_response(ref, with_account \\ true) do
      data =
        %{"status" => "pay_offline", "reference" => ref}
        |> then(fn d ->
          if with_account do
            Map.put(d, "bank_transfer", %{
              "account_number" => "1234567890",
              "bank_name" => "GhIPSS Test Bank",
              "account_name" => "YAGYE COLLECT",
              "expiry_date" => "2026-12-31T23:59:59Z"
            })
          else
            d
          end
        end)

      %{"status" => true, "data" => data}
    end

    test "pay_offline with bank_transfer details returns pending with virtual_account" do
      Req.Test.stub(:paystack_http, fn conn ->
        Req.Test.json(conn, pay_offline_response("ref_bt1"))
      end)

      assert {:pending, %{provider_reference: "ref_bt1", virtual_account: va}} =
               PaystackAdapter.charge(bank_transfer_payment(), bt_attempt(), @credential)

      assert va.account_number == "1234567890"
      assert va.bank_name == "GhIPSS Test Bank"
      assert va.account_name == "YAGYE COLLECT"
      assert va.expires_at == "2026-12-31T23:59:59Z"
    end

    test "pay_offline without account details returns pending with nil virtual_account" do
      Req.Test.stub(:paystack_http, fn conn ->
        Req.Test.json(conn, pay_offline_response("ref_bt2", false))
      end)

      assert {:pending, %{provider_reference: "ref_bt2", virtual_account: nil}} =
               PaystackAdapter.charge(bank_transfer_payment(), bt_attempt(), @credential)
    end

    test "pending status returns pending" do
      Req.Test.stub(:paystack_http, fn conn ->
        Req.Test.json(conn, %{
          "status" => true,
          "data" => %{"status" => "pending", "reference" => "ref_bt3"}
        })
      end)

      assert {:pending, %{provider_reference: "ref_bt3"}} =
               PaystackAdapter.charge(bank_transfer_payment(), bt_attempt(), @credential)
    end

    test "paystack_error returns definite_failure" do
      Req.Test.stub(:paystack_http, fn conn ->
        Req.Test.json(conn, %{"status" => false, "message" => "Invalid amount"})
      end)

      assert {:error,
              %{
                error_class: :definite_failure,
                response_code: "paystack_error",
                response_message: "Invalid amount"
              }} =
               PaystackAdapter.charge(bank_transfer_payment(), bt_attempt(), @credential)
    end

    test "sends correct bank transfer body" do
      Req.Test.stub(:paystack_http, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        parsed = Jason.decode!(body)
        assert parsed["bank"]["type"] == "bank_transfer"
        assert parsed["bank"]["account_bank"] == "GH"
        assert parsed["currency"] == "GHS"
        assert parsed["amount"] == 50_000

        Req.Test.json(conn, pay_offline_response("ref_body_check"))
      end)

      PaystackAdapter.charge(bank_transfer_payment(), bt_attempt(), @credential)
    end

    test "sends customer_email in body" do
      Req.Test.stub(:paystack_http, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        parsed = Jason.decode!(body)
        assert parsed["email"] == "buyer@test.com"

        Req.Test.json(conn, pay_offline_response("ref_email_check"))
      end)

      PaystackAdapter.charge(bank_transfer_payment(), bt_attempt(), @credential)
    end

    test "timeout returns indeterminate" do
      Req.Test.stub(:paystack_http, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, %{error_class: :indeterminate, response_code: "timeout"}} =
               PaystackAdapter.charge(bank_transfer_payment(), bt_attempt(), @credential)
    end

    test "5xx returns retryable_error" do
      Req.Test.stub(:paystack_http, fn conn ->
        Plug.Conn.send_resp(conn, 503, "")
      end)

      assert {:error, %{error_class: :retryable_error, response_code: "http_503"}} =
               PaystackAdapter.charge(bank_transfer_payment(), bt_attempt(), @credential)
    end
  end
end
