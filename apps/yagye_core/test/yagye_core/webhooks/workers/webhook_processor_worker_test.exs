defmodule YagyeCore.Webhooks.Workers.WebhookProcessorWorkerTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.Payments
  alias YagyeCore.Payments.Schemas.PaymentAttempt
  alias YagyeCore.Repo
  alias YagyeCore.Webhooks
  alias YagyeCore.Webhooks.Workers.WebhookProcessorWorker

  # Sets up a payment in requires_action state with an attempt carrying a
  # provider_reference — the exact state the real flow produces after
  # PaymentDispatchWorker receives {:pending, ...} from the adapter.
  defp pending_auth_fixture do
    merchant = Fixtures.approved_merchant_fixture()
    provider = Fixtures.simulator_provider_fixture()
    payment = Fixtures.payment_fixture(merchant)
    {:ok, attempt} = Payments.create_attempt(payment, provider.id)
    charge_ref = "chg_#{System.unique_integer([:positive])}"

    {:ok, payment} =
      Payments.handle_pending_auth(payment, attempt, %{provider_reference: charge_ref})

    attempt = Repo.get!(PaymentAttempt, attempt.id)

    %{payment: payment, attempt: attempt, charge_ref: charge_ref}
  end

  defp insert_webhook(event_type, charge_ref) do
    provider_code = "simulator"
    event_id = "evt_#{System.unique_integer([:positive])}"

    raw_body =
      Jason.encode!(%{
        "charge_ref" => charge_ref,
        "event_type" => event_type,
        "auth_code" => "AUTH123"
      })

    {:ok, webhook} =
      Webhooks.receive_webhook(provider_code, event_id, event_type, raw_body)

    webhook
  end

  defp run_worker(webhook) do
    WebhookProcessorWorker.perform(%Oban.Job{args: %{"webhook_event_id" => webhook.id}})
  end

  describe "charge.succeeded" do
    test "transitions payment to succeeded" do
      %{payment: payment, charge_ref: charge_ref} = pending_auth_fixture()
      webhook = insert_webhook("charge.succeeded", charge_ref)

      assert :ok = run_worker(webhook)

      updated = Repo.get!(YagyeCore.Payments.Schemas.Payment, payment.id)
      assert updated.state == "succeeded"
    end

    test "marks the webhook event as processed" do
      %{charge_ref: charge_ref} = pending_auth_fixture()
      webhook = insert_webhook("charge.succeeded", charge_ref)

      run_worker(webhook)

      updated = Repo.reload!(webhook)
      assert updated.state == "processed"
      assert updated.processed_at != nil
    end
  end

  describe "charge.failed" do
    test "transitions payment to failed" do
      %{payment: payment, charge_ref: charge_ref} = pending_auth_fixture()

      raw_body =
        Jason.encode!(%{
          "charge_ref" => charge_ref,
          "event_type" => "charge.failed",
          "decline_code" => "insufficient_funds"
        })

      event_id = "evt_#{System.unique_integer([:positive])}"
      {:ok, webhook} = Webhooks.receive_webhook("simulator", event_id, "charge.failed", raw_body)

      assert :ok = run_worker(webhook)

      updated = Repo.get!(YagyeCore.Payments.Schemas.Payment, payment.id)
      assert updated.state == "failed"
    end

    test "marks the webhook event as processed" do
      %{charge_ref: charge_ref} = pending_auth_fixture()

      raw_body = Jason.encode!(%{"charge_ref" => charge_ref, "event_type" => "charge.failed"})
      event_id = "evt_#{System.unique_integer([:positive])}"
      {:ok, webhook} = Webhooks.receive_webhook("simulator", event_id, "charge.failed", raw_body)

      run_worker(webhook)

      updated = Repo.reload!(webhook)
      assert updated.state == "processed"
    end
  end

  describe "unknown event_type" do
    test "returns an error tuple" do
      event_id = "evt_#{System.unique_integer([:positive])}"
      raw_body = Jason.encode!(%{"charge_ref" => "chg_001"})

      {:ok, webhook} =
        Webhooks.receive_webhook("simulator", event_id, "some.unknown.event", raw_body)

      assert {:error, {:unknown_event_type, "some.unknown.event"}} = run_worker(webhook)
    end

    test "marks the webhook event as failed" do
      event_id = "evt_#{System.unique_integer([:positive])}"
      raw_body = Jason.encode!(%{"charge_ref" => "chg_001"})
      {:ok, webhook} = Webhooks.receive_webhook("simulator", event_id, "unknown.event", raw_body)

      run_worker(webhook)

      updated = Repo.reload!(webhook)
      assert updated.state == "failed"
      assert updated.error =~ "unknown_event_type"
    end
  end
end
