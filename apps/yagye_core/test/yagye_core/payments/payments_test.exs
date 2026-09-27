defmodule YagyeCore.Payments.PaymentsTest do
  use YagyeCore.DataCase, async: true

  import Mox

  alias YagyeCore.{Fixtures, Payments, Repo}
  alias YagyeCore.Payments.Schemas.{Payment, PaymentMobileMoneyDetails}
  alias YagyeCore.Payments.Workers.PaymentDispatchWorker

  setup :verify_on_exit!

  describe "create_payment/2" do
    test "creates payment with valid attrs" do
      merchant = Fixtures.merchant_fixture()

      assert {:ok, {payment, event}} =
               Payments.create_payment(merchant.id, %{
                 amount: 10_000,
                 currency: "GHS",
                 rail: "fiat_provider",
                 method: "mobile_money"
               })

      assert payment.amount == 10_000
      assert payment.currency == "GHS"
      assert payment.state == "created"
      assert payment.mode == "simulation"
      assert payment.version == 0
      assert String.starts_with?(payment.public_id, "pay_")
      assert event.event_type == "payment.created"
      assert event.to_state == "created"
    end

    test "enqueues dispatch worker after creation" do
      merchant = Fixtures.merchant_fixture()

      assert {:ok, {payment, _event}} =
               Payments.create_payment(merchant.id, %{
                 amount: 10_000,
                 currency: "GHS",
                 rail: "fiat_provider",
                 method: "mobile_money"
               })

      assert_enqueued(worker: PaymentDispatchWorker, args: %{payment_id: payment.id})
    end

    test "accepts optional fields" do
      merchant = Fixtures.merchant_fixture()

      assert {:ok, {payment, _}} =
               Payments.create_payment(merchant.id, %{
                 amount: 500,
                 currency: "GHS",
                 rail: "fiat_provider",
                 method: "mobile_money",
                 merchant_reference: "order_001",
                 description: "Test payment",
                 metadata: %{"order_type" => "digital"}
               })

      assert payment.method == "mobile_money"
      assert payment.merchant_reference == "order_001"
      assert payment.description == "Test payment"
      assert payment.metadata == %{"order_type" => "digital"}
    end

    test "returns error when amount is zero" do
      merchant = Fixtures.merchant_fixture()

      assert {:error, changeset} =
               Payments.create_payment(merchant.id, %{
                 amount: 0,
                 currency: "GHS",
                 rail: "fiat_provider",
                 method: "mobile_money"
               })

      assert %{amount: _} = errors_on(changeset)
    end

    test "returns error when currency is invalid length" do
      merchant = Fixtures.merchant_fixture()

      assert {:error, changeset} =
               Payments.create_payment(merchant.id, %{
                 amount: 100,
                 currency: "GHSC",
                 rail: "fiat_provider",
                 method: "mobile_money"
               })

      assert %{currency: _} = errors_on(changeset)
    end

    test "returns error when rail is invalid" do
      merchant = Fixtures.merchant_fixture()

      assert {:error, changeset} =
               Payments.create_payment(merchant.id, %{
                 amount: 100,
                 currency: "GHS",
                 rail: "crypto",
                 method: "mobile_money"
               })

      assert %{rail: _} = errors_on(changeset)
    end

    test "returns error when merchant does not exist" do
      assert {:error, :merchant_not_found} =
               Payments.create_payment(Uniq.UUID.uuid7(), %{
                 amount: 100,
                 currency: "GHS",
                 rail: "fiat_provider",
                 method: "mobile_money"
               })
    end

    test "enforces unique merchant_reference per merchant" do
      merchant = Fixtures.merchant_fixture()

      attrs = %{
        amount: 100,
        currency: "GHS",
        rail: "fiat_provider",
        method: "mobile_money",
        merchant_reference: "ref_001"
      }

      assert {:ok, _} = Payments.create_payment(merchant.id, attrs)
      assert {:error, changeset} = Payments.create_payment(merchant.id, attrs)
      assert %{merchant_id: _} = errors_on(changeset)
    end
  end

  describe "dispatch_payment/1" do
    test "transitions payment from created to processing" do
      merchant = Fixtures.merchant_fixture()
      payment = Fixtures.payment_fixture(merchant)

      assert {:ok, updated} = Payments.dispatch_payment(payment.id)

      assert updated.state == "processing"
      assert updated.version == 1
    end

    test "is idempotent — returns ok if already processing" do
      merchant = Fixtures.merchant_fixture()
      payment = Fixtures.payment_fixture(merchant)
      {:ok, _} = Payments.dispatch_payment(payment.id)

      assert {:ok, updated} = Payments.dispatch_payment(payment.id)
      assert updated.state == "processing"
    end

    test "returns not_found for unknown payment id" do
      assert {:error, :not_found} = Payments.dispatch_payment(Uniq.UUID.uuid7())
    end
  end

  describe "handle_provider_response/3 — success" do
    setup do
      provider = Fixtures.simulator_provider_fixture()
      merchant = Fixtures.merchant_fixture()
      payment = Fixtures.payment_fixture(merchant)
      {:ok, payment} = Payments.dispatch_payment(payment.id)
      {:ok, attempt} = Payments.create_attempt(payment, provider.id)
      %{payment: payment, attempt: attempt}
    end

    test "transitions payment to succeeded and writes four events", %{
      payment: payment,
      attempt: attempt
    } do
      result = {:ok, %{provider_reference: "gw_ref_123", auth_code: "AUTH"}}

      assert {:ok, updated} = Payments.handle_provider_response(payment, attempt, result)

      assert updated.state == "succeeded"
      assert updated.version == 3

      assert {:ok, events} = Payments.list_events(payment.id)
      assert length(events) == 4

      assert Enum.map(events, & &1.event_type) ==
               [
                 "payment.created",
                 "payment.processing",
                 "payment.authorised",
                 "payment.succeeded"
               ]

      assert Enum.map(events, &{&1.from_state, &1.to_state}) == [
               {nil, "created"},
               {"created", "processing"},
               {"processing", "authorised"},
               {"authorised", "succeeded"}
             ]
    end
  end

  describe "handle_provider_response/3 — failure" do
    setup do
      provider = Fixtures.simulator_provider_fixture()
      merchant = Fixtures.merchant_fixture()
      payment = Fixtures.payment_fixture(merchant)
      {:ok, payment} = Payments.dispatch_payment(payment.id)
      {:ok, attempt} = Payments.create_attempt(payment, provider.id)
      %{payment: payment, attempt: attempt}
    end

    test "transitions to failed on definite failure", %{payment: payment, attempt: attempt} do
      result =
        {:error,
         %{error_class: :definite_failure, response_code: "DO_NOT_HONOR", response_message: nil}}

      assert {:ok, updated} = Payments.handle_provider_response(payment, attempt, result)
      assert updated.state == "failed"
    end

    test "transitions to indeterminate on timeout", %{payment: payment, attempt: attempt} do
      result =
        {:error, %{error_class: :indeterminate, response_code: "timeout", response_message: nil}}

      assert {:ok, updated} = Payments.handle_provider_response(payment, attempt, result)
      assert updated.state == "indeterminate"
    end

    test "returns retryable error without changing payment state", %{
      payment: payment,
      attempt: attempt
    } do
      result =
        {:error,
         %{error_class: :retryable_error, response_code: "GATEWAY_ERROR", response_message: nil}}

      assert {:error, :retryable_error} =
               Payments.handle_provider_response(payment, attempt, result)

      assert {:ok, reloaded} = Payments.get_payment(payment.public_id)
      assert reloaded.state == "processing"
    end
  end

  describe "get_payment/1" do
    test "returns payment by public_id" do
      merchant = Fixtures.merchant_fixture()
      payment = Fixtures.payment_fixture(merchant)

      assert {:ok, found} = Payments.get_payment(payment.public_id)
      assert found.id == payment.id
    end

    test "returns not_found for unknown public_id" do
      assert {:error, :not_found} = Payments.get_payment("pay_nonexistent")
    end
  end

  # ── handle_pending_auth/3 — MoMo details row ─────────────────────────────────

  describe "handle_pending_auth/3 — payment_mobile_money_details insert" do
    setup do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()

      payment =
        Fixtures.payment_fixture(merchant, %{
          method: "mobile_money",
          metadata: %{"network" => "MTN", "msisdn" => "0241000001"}
        })

      {:ok, payment} = payment |> Payment.transition_changeset("processing") |> Repo.update()
      {:ok, attempt} = Payments.create_attempt(payment, provider.id)
      %{payment: payment, attempt: attempt}
    end

    test "inserts a momo_details row with masked MSISDN and network_reference", %{
      payment: payment,
      attempt: attempt
    } do
      charge_ref = "test-charge-ref-#{System.unique_integer()}"

      assert {:ok, _} =
               Payments.handle_pending_auth(payment, attempt, %{provider_reference: charge_ref})

      details = Repo.get(PaymentMobileMoneyDetails, payment.id)
      assert details != nil
      assert details.network == "mtn"
      assert details.network_reference == charge_ref
      assert details.msisdn_masked =~ ~r/233XX+\d{4}/
      assert byte_size(details.msisdn_hash) == 64
      assert details.charge_bearer == "merchant"
      assert details.financial_transaction_id == nil
    end

    test "normalises TELECEL/VODAFONE network strings to telecel" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()

      for raw_network <- ["TELECEL", "VODAFONE"] do
        payment =
          Fixtures.payment_fixture(merchant, %{
            method: "mobile_money",
            metadata: %{"network" => raw_network, "msisdn" => "0551000001"}
          })

        {:ok, payment} = payment |> Payment.transition_changeset("processing") |> Repo.update()
        {:ok, attempt} = Payments.create_attempt(payment, provider.id)
        ref = "ref-net-#{System.unique_integer([:positive])}"

        assert {:ok, _} =
                 Payments.handle_pending_auth(payment, attempt, %{provider_reference: ref})

        details = Repo.get!(PaymentMobileMoneyDetails, payment.id)
        assert details.network == "telecel", "expected telecel for #{raw_network}"
      end
    end

    test "skips insert when MSISDN is absent in payment metadata" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()

      payment =
        Fixtures.payment_fixture(merchant, %{
          method: "mobile_money",
          metadata: %{"network" => "MTN"}
        })

      {:ok, payment} = payment |> Payment.transition_changeset("processing") |> Repo.update()
      {:ok, attempt} = Payments.create_attempt(payment, provider.id)

      assert {:ok, _} =
               Payments.handle_pending_auth(payment, attempt, %{
                 provider_reference: "ref-no-msisdn"
               })

      assert Repo.get(PaymentMobileMoneyDetails, payment.id) == nil
    end

    test "skips insert for non-mobile_money payment method" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()

      payment =
        Fixtures.payment_fixture(merchant, %{
          method: "mobile_money",
          metadata: %{"network" => "MTN", "msisdn" => "0241000001"}
        })

      {:ok, payment} = payment |> Payment.transition_changeset("processing") |> Repo.update()
      payment = %{payment | method: "bank_transfer"}
      {:ok, attempt} = Payments.create_attempt(payment, provider.id)

      assert {:ok, _} =
               Payments.handle_pending_auth(payment, attempt, %{provider_reference: "ref-bank"})

      assert Repo.get(PaymentMobileMoneyDetails, payment.id) == nil
    end
  end

  # ── handle_provider_response/3 — financial_transaction_id ────────────────────

  describe "handle_provider_response/3 — financial_transaction_id written on success" do
    setup do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()

      payment =
        Fixtures.payment_fixture(merchant, %{
          method: "mobile_money",
          metadata: %{"network" => "MTN", "msisdn" => "0241000001"}
        })

      {:ok, payment} = Payments.dispatch_payment(payment.id)
      {:ok, attempt} = Payments.create_attempt(payment, provider.id)

      # Simulate the RequestToPay being sent (inserts the momo_details row)
      {:ok, _} =
        Payments.handle_pending_auth(payment, attempt, %{provider_reference: "pend-ref"})

      {:ok, payment} = Payments.get_payment(payment.public_id)
      %{payment: payment, attempt: attempt}
    end

    test "writes financialTransactionId and approved_at on SUCCESSFUL query", %{
      payment: payment,
      attempt: attempt
    } do
      result = {:ok, %{provider_reference: "ext-ref", auth_code: "fin-tx-mtn-12345"}}

      assert {:ok, updated} = Payments.handle_provider_response(payment, attempt, result)
      assert updated.state == "succeeded"

      details = Repo.get(PaymentMobileMoneyDetails, payment.id)
      assert details.financial_transaction_id == "fin-tx-mtn-12345"
      assert details.approved_at != nil
    end

    test "skips financial_transaction_id update when auth_code is nil", %{
      payment: payment,
      attempt: attempt
    } do
      result = {:ok, %{provider_reference: "ext-ref", auth_code: nil}}

      assert {:ok, _} = Payments.handle_provider_response(payment, attempt, result)

      details = Repo.get(PaymentMobileMoneyDetails, payment.id)
      assert details.financial_transaction_id == nil
    end

    test "succeeds without momo_details row when MSISDN was absent" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()

      payment =
        Fixtures.payment_fixture(merchant, %{
          method: "mobile_money",
          metadata: %{"network" => "MTN"}
        })

      {:ok, payment} = Payments.dispatch_payment(payment.id)
      {:ok, attempt} = Payments.create_attempt(payment, provider.id)
      {:ok, payment} = Payments.get_payment(payment.public_id)

      result = {:ok, %{provider_reference: "ext-ref", auth_code: "fin-tx-99"}}

      assert {:ok, succeeded} = Payments.handle_provider_response(payment, attempt, result)
      assert succeeded.state == "succeeded"
      assert Repo.get(PaymentMobileMoneyDetails, payment.id) == nil
    end
  end
end
