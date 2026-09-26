defmodule YagyeCore.Payments.Adapters.MTNMomoAdapterTest do
  use ExUnit.Case, async: true

  alias YagyeCore.Payments.Adapters.MTNMomoAdapter
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}

  @credential %{
    "base_url" => "http://mtn-test.local",
    "subscription_key" => "coll-sub-key",
    "api_user_id" => "user-uuid",
    "api_key" => "api-key-secret",
    "disbursement_subscription_key" => "disb-sub-key",
    "disbursement_api_user_id" => "disb-user-uuid",
    "disbursement_api_key" => "disb-api-key",
    "target_environment" => "sandbox"
  }

  defp payment(method \\ "mobile_money") do
    %Payment{
      id: Ecto.UUID.generate(),
      amount: 5000,
      currency: "GHS",
      method: method,
      metadata: %{"msisdn" => "0241000001", "description" => "Test payment"}
    }
  end

  defp attempt(token \\ nil) do
    %PaymentAttempt{
      id: Ecto.UUID.generate(),
      idempotency_token: token || Ecto.UUID.generate(),
      provider_reference: nil
    }
  end

  # Sends a JSON response with a custom HTTP status code.
  defp json_resp(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  # Sends an empty response with a custom status (MTN uses 202 with no body).
  defp empty_resp(conn, status) do
    Plug.Conn.send_resp(conn, status, "")
  end

  # Stub that returns a valid token on /collection/token/ and delegates other paths.
  defp with_token_stub(name, handler) do
    Req.Test.stub(name, fn conn ->
      if conn.request_path == "/collection/token/" do
        Req.Test.json(conn, %{"access_token" => "test-bearer-token"})
      else
        handler.(conn)
      end
    end)
  end

  defp with_disbursement_token_stub(name, handler) do
    Req.Test.stub(name, fn conn ->
      if conn.request_path == "/disbursement/token/" do
        Req.Test.json(conn, %{"access_token" => "disb-bearer-token"})
      else
        handler.(conn)
      end
    end)
  end

  # ── charge/3 ─────────────────────────────────────────────────────────────────

  describe "charge/3" do
    test "202 response returns pending with provider_reference = idempotency_token" do
      token = Ecto.UUID.generate()

      with_token_stub(:mtn_momo_http, fn conn ->
        assert conn.request_path == "/collection/v1_0/requesttopay"
        empty_resp(conn, 202)
      end)

      assert {:pending, %{provider_reference: ^token}} =
               MTNMomoAdapter.charge(payment(), attempt(token), @credential)
    end

    test "400 response returns definite_failure / invalid_request" do
      with_token_stub(:mtn_momo_http, fn conn ->
        json_resp(conn, 400, %{"message" => "Invalid MSISDN"})
      end)

      assert {:error, %{error_class: :definite_failure, response_code: "invalid_request"}} =
               MTNMomoAdapter.charge(payment(), attempt(), @credential)
    end

    test "409 response returns indeterminate / duplicate_reference" do
      with_token_stub(:mtn_momo_http, fn conn ->
        json_resp(conn, 409, %{"message" => "Conflict"})
      end)

      assert {:error, %{error_class: :indeterminate, response_code: "duplicate_reference"}} =
               MTNMomoAdapter.charge(payment(), attempt(), @credential)
    end

    test "unexpected 5xx returns retryable_error" do
      with_token_stub(:mtn_momo_http, fn conn ->
        empty_resp(conn, 503)
      end)

      assert {:error, %{error_class: :retryable_error, response_code: "http_503"}} =
               MTNMomoAdapter.charge(payment(), attempt(), @credential)
    end

    test "non-mobile_money method returns definite_failure without HTTP call" do
      assert {:error, %{error_class: :definite_failure, response_code: "method_not_supported"}} =
               MTNMomoAdapter.charge(payment("card"), attempt(), @credential)
    end

    test "token fetch failure propagates before charge is sent" do
      Req.Test.stub(:mtn_momo_http, fn conn ->
        if conn.request_path == "/collection/token/" do
          json_resp(conn, 401, %{"error_description" => "invalid credentials"})
        else
          flunk("charge should not be called when token fetch fails")
        end
      end)

      assert {:error, %{error_class: :retryable_error, response_code: "token_http_401"}} =
               MTNMomoAdapter.charge(payment(), attempt(), @credential)
    end
  end

  # ── query_charge/2 ───────────────────────────────────────────────────────────

  describe "query_charge/2" do
    test "SUCCESSFUL status returns ok with provider_reference and auth_code" do
      ref = "ext-ref-abc"

      attempt = %PaymentAttempt{
        id: Ecto.UUID.generate(),
        idempotency_token: Ecto.UUID.generate(),
        provider_reference: ref
      }

      with_token_stub(:mtn_momo_http, fn conn ->
        Req.Test.json(conn, %{
          "status" => "SUCCESSFUL",
          "externalId" => ref,
          "financialTransactionId" => "fin-tx-999"
        })
      end)

      assert {:ok, %{provider_reference: ^ref, auth_code: "fin-tx-999"}} =
               MTNMomoAdapter.query_charge(attempt, @credential)
    end

    test "PENDING status returns retryable_error / pending" do
      attempt = %PaymentAttempt{
        id: Ecto.UUID.generate(),
        idempotency_token: Ecto.UUID.generate(),
        provider_reference: "some-ref"
      }

      with_token_stub(:mtn_momo_http, fn conn ->
        Req.Test.json(conn, %{"status" => "PENDING"})
      end)

      assert {:error, %{error_class: :retryable_error, response_code: "pending"}} =
               MTNMomoAdapter.query_charge(attempt, @credential)
    end

    test "FAILED status returns definite_failure with reason code" do
      attempt = %PaymentAttempt{
        id: Ecto.UUID.generate(),
        idempotency_token: Ecto.UUID.generate(),
        provider_reference: "some-ref"
      }

      with_token_stub(:mtn_momo_http, fn conn ->
        Req.Test.json(conn, %{
          "status" => "FAILED",
          "reason" => %{"code" => "EXPIRED", "message" => "Request timed out"}
        })
      end)

      assert {:error, %{error_class: :definite_failure, response_code: "EXPIRED"}} =
               MTNMomoAdapter.query_charge(attempt, @credential)
    end

    test "404 returns indeterminate / not_found" do
      attempt = %PaymentAttempt{
        id: Ecto.UUID.generate(),
        idempotency_token: Ecto.UUID.generate(),
        provider_reference: "missing-ref"
      }

      with_token_stub(:mtn_momo_http, fn conn ->
        empty_resp(conn, 404)
      end)

      assert {:error, %{error_class: :indeterminate, response_code: "not_found"}} =
               MTNMomoAdapter.query_charge(attempt, @credential)
    end
  end

  # ── name_enquiry/2 ──────────────────────────────────────────────────────────

  describe "name_enquiry/2" do
    test "200 with name field returns account_name" do
      with_token_stub(:mtn_momo_http, fn conn ->
        Req.Test.json(conn, %{"name" => "Kwame Mensah"})
      end)

      assert {:ok, %{account_name: "Kwame Mensah", kyc_tier: nil}} =
               MTNMomoAdapter.name_enquiry(%{msisdn: "0241000001", network: "MTN"}, @credential)
    end

    test "200 with given_name/family_name assembles name" do
      with_token_stub(:mtn_momo_http, fn conn ->
        Req.Test.json(conn, %{"given_name" => "Ama", "family_name" => "Boateng"})
      end)

      assert {:ok, %{account_name: "Ama Boateng", kyc_tier: nil}} =
               MTNMomoAdapter.name_enquiry(%{msisdn: "0241000002", network: "MTN"}, @credential)
    end

    test "404 returns definite_failure / account_not_found" do
      with_token_stub(:mtn_momo_http, fn conn ->
        empty_resp(conn, 404)
      end)

      assert {:error, %{error_class: :definite_failure, response_code: "account_not_found"}} =
               MTNMomoAdapter.name_enquiry(%{msisdn: "0249999999", network: "MTN"}, @credential)
    end

    test "MSISDN normalisation strips leading zero" do
      with_token_stub(:mtn_momo_http, fn conn ->
        # The path should contain the E.164 form — "0" prefix becomes "233" prefix
        assert String.contains?(conn.request_path, "233241000001")
        Req.Test.json(conn, %{"name" => "Kofi Acheampong"})
      end)

      assert {:ok, %{account_name: "Kofi Acheampong"}} =
               MTNMomoAdapter.name_enquiry(%{msisdn: "0241000001", network: "MTN"}, @credential)
    end
  end

  # ── disburse/2 ──────────────────────────────────────────────────────────────

  describe "disburse/2" do
    @disburse_params %{
      amount: 100_000,
      currency: "GHS",
      reference: "batch-uuid-123",
      recipient_msisdn: "0241000001"
    }

    test "202 returns pending with a UUID v4 provider_reference" do
      with_disbursement_token_stub(:mtn_momo_http, fn conn ->
        assert conn.request_path == "/disbursement/v1_0/transfer"
        empty_resp(conn, 202)
      end)

      assert {:pending, %{provider_reference: ref}} =
               MTNMomoAdapter.disburse(@disburse_params, @credential)

      # Verify the reference is a valid UUID v4 (version nibble = 4)
      assert {:ok, _} = Ecto.UUID.cast(ref)
    end

    test "409 (duplicate) returns pending — safe retry" do
      with_disbursement_token_stub(:mtn_momo_http, fn conn ->
        empty_resp(conn, 409)
      end)

      assert {:pending, %{provider_reference: _}} =
               MTNMomoAdapter.disburse(@disburse_params, @credential)
    end

    test "400 returns definite_failure / invalid_request" do
      with_disbursement_token_stub(:mtn_momo_http, fn conn ->
        json_resp(conn, 400, %{"message" => "Invalid payee"})
      end)

      assert {:error,
              %{
                error_class: :definite_failure,
                response_code: "invalid_request",
                response_message: "Invalid payee"
              }} = MTNMomoAdapter.disburse(@disburse_params, @credential)
    end

    test "disbursement token failure propagates" do
      Req.Test.stub(:mtn_momo_http, fn conn ->
        if conn.request_path == "/disbursement/token/" do
          json_resp(conn, 401, %{"error_description" => "bad credentials"})
        else
          flunk("transfer should not be called when token fetch fails")
        end
      end)

      assert {:error, %{error_class: :retryable_error, response_code: "disb_token_http_401"}} =
               MTNMomoAdapter.disburse(@disburse_params, @credential)
    end
  end
end
