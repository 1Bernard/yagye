defmodule YagyeCore.Payments.Adapters.MTNMomoAdapterSandboxTest do
  # async: false because we temporarily modify application env to bypass Req.Test intercept.
  # Run with: mix test --include sandbox
  use ExUnit.Case, async: false

  @moduletag :sandbox

  alias YagyeCore.Payments.Adapters.MTNMomoAdapter
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}

  setup do
    sub_key = System.get_env("MTN_SANDBOX_COLLECTION_SUBSCRIPTION_KEY")

    unless sub_key do
      raise """
      MTN sandbox credentials not set. Export these env vars then run:

        MTN_SANDBOX_COLLECTION_SUBSCRIPTION_KEY=...
        MTN_SANDBOX_COLLECTION_API_USER_ID=...
        MTN_SANDBOX_COLLECTION_API_KEY=...
        mix test --include sandbox

      Optional (fall back to collection creds if not set):
        MTN_SANDBOX_DISBURSEMENT_SUBSCRIPTION_KEY=...
        MTN_SANDBOX_DISBURSEMENT_API_USER_ID=...
        MTN_SANDBOX_DISBURSEMENT_API_KEY=...
        MTN_SANDBOX_TEST_MSISDN=...         (default: 0241000001)
        MTN_SANDBOX_BASE_URL=...            (default: https://sandbox.momodeveloper.mtn.com)
      """
    end

    credential = %{
      "base_url" =>
        System.get_env("MTN_SANDBOX_BASE_URL", "https://sandbox.momodeveloper.mtn.com"),
      "subscription_key" => sub_key,
      "api_user_id" => System.get_env("MTN_SANDBOX_COLLECTION_API_USER_ID"),
      "api_key" => System.get_env("MTN_SANDBOX_COLLECTION_API_KEY"),
      "disbursement_subscription_key" =>
        System.get_env("MTN_SANDBOX_DISBURSEMENT_SUBSCRIPTION_KEY", sub_key),
      "disbursement_api_user_id" =>
        System.get_env(
          "MTN_SANDBOX_DISBURSEMENT_API_USER_ID",
          System.get_env("MTN_SANDBOX_COLLECTION_API_USER_ID")
        ),
      "disbursement_api_key" =>
        System.get_env(
          "MTN_SANDBOX_DISBURSEMENT_API_KEY",
          System.get_env("MTN_SANDBOX_COLLECTION_API_KEY")
        ),
      "target_environment" => "sandbox"
    }

    # Remove the Req.Test plug so real HTTP calls reach the MTN sandbox.
    original_opts = Application.get_env(:yagye_core, :mtn_momo_req_opts)
    Application.put_env(:yagye_core, :mtn_momo_req_opts, [])
    on_exit(fn -> Application.put_env(:yagye_core, :mtn_momo_req_opts, original_opts) end)

    test_msisdn = System.get_env("MTN_SANDBOX_TEST_MSISDN", "0241000001")

    %{credential: credential, test_msisdn: test_msisdn}
  end

  # ── charge/3 ─────────────────────────────────────────────────────────────────

  describe "charge/3 — real MTN sandbox" do
    test "RequestToPay accepted: returns pending with our UUID as provider_reference", %{
      credential: credential,
      test_msisdn: msisdn
    } do
      idempotency_token = Ecto.UUID.generate()

      payment = %Payment{
        id: Ecto.UUID.generate(),
        # MTN sandbox only accepts EUR; GHS is production-only (see adapter docs).
        amount: 100,
        currency: "EUR",
        method: "mobile_money",
        metadata: %{"msisdn" => msisdn, "description" => "Sandbox charge test"}
      }

      attempt = %PaymentAttempt{
        id: Ecto.UUID.generate(),
        idempotency_token: idempotency_token,
        provider_reference: nil
      }

      result = MTNMomoAdapter.charge(payment, attempt, credential)

      assert {:pending, %{provider_reference: ref}} = result
      # The reference echoed back must be the idempotency token we sent as X-Reference-Id.
      assert ref == idempotency_token
      # Must be a valid UUID so our DB can store it.
      assert {:ok, _} = Ecto.UUID.cast(ref)
    end
  end

  # ── query_charge/2 ────────────────────────────────────────────────────────────

  describe "query_charge/2 — real MTN sandbox" do
    test "polls until SUCCESSFUL and returns a non-nil financialTransactionId", %{
      credential: credential,
      test_msisdn: msisdn
    } do
      payment = %Payment{
        id: Ecto.UUID.generate(),
        amount: 100,
        currency: "EUR",
        method: "mobile_money",
        metadata: %{"msisdn" => msisdn, "description" => "Sandbox poll test"}
      }

      attempt = %PaymentAttempt{
        id: Ecto.UUID.generate(),
        idempotency_token: Ecto.UUID.generate(),
        provider_reference: nil
      }

      {:pending, %{provider_reference: ref}} = MTNMomoAdapter.charge(payment, attempt, credential)

      poll_attempt = %{attempt | provider_reference: ref}

      assert {:ok, %{provider_reference: ^ref, auth_code: fin_id}} =
               poll_until_final(poll_attempt, credential)

      # financialTransactionId is the MTN-internal reference needed for reconciliation.
      assert is_binary(fin_id) and fin_id != ""
    end
  end

  # ── name_enquiry/2 ────────────────────────────────────────────────────────────

  describe "name_enquiry/2 — real MTN sandbox" do
    test "returns account_name for a sandbox MSISDN", %{
      credential: credential,
      test_msisdn: msisdn
    } do
      result = MTNMomoAdapter.name_enquiry(%{msisdn: msisdn, network: "MTN"}, credential)

      # Sandbox may return a name or 404 depending on provisioning — both are valid responses.
      assert match?({:ok, %{account_name: name}} when is_binary(name), result) or
               match?(
                 {:error, %{error_class: :definite_failure, response_code: "account_not_found"}},
                 result
               )
    end
  end

  # ── Polling helper ────────────────────────────────────────────────────────────

  # MTN sandbox auto-approves RequestToPay; this polls every 2s, up to 30s.
  defp poll_until_final(attempt, credential, retries \\ 15) do
    case MTNMomoAdapter.query_charge(attempt, credential) do
      {:ok, _} = ok ->
        ok

      {:error, %{error_class: :retryable_error, response_code: "pending"}} when retries > 0 ->
        Process.sleep(2_000)
        poll_until_final(attempt, credential, retries - 1)

      {:error, _} = err ->
        err
    end
  end
end
