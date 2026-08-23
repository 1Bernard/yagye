defmodule YagyeCore.Webhooks.WebhooksTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Repo
  alias YagyeCore.Webhooks
  alias YagyeCore.Webhooks.Schemas.WebhookEvent

  defp event_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        provider_code: "simulator",
        event_id: "evt_#{System.unique_integer([:positive])}",
        event_type: "charge.succeeded",
        raw_body: ~s({"charge_ref":"chg_001"})
      },
      overrides
    )
  end

  describe "receive_webhook/5" do
    test "inserts a pending webhook event on first receipt" do
      attrs = event_attrs()

      assert {:ok, webhook} =
               Webhooks.receive_webhook(
                 attrs.provider_code,
                 attrs.event_id,
                 attrs.event_type,
                 attrs.raw_body
               )

      assert webhook.state == "pending"
      assert webhook.provider_code == attrs.provider_code
      assert webhook.event_id == attrs.event_id
      assert webhook.event_type == attrs.event_type
      assert webhook.raw_body == attrs.raw_body
    end

    test "defaults signature_valid to true and attempt_count to 1" do
      attrs = event_attrs()

      {:ok, webhook} =
        Webhooks.receive_webhook(
          attrs.provider_code,
          attrs.event_id,
          attrs.event_type,
          attrs.raw_body
        )

      assert webhook.signature_valid == true
      assert webhook.attempt_count == 1
    end

    test "stores explicit signature_valid and attempt_count" do
      attrs = event_attrs()

      {:ok, webhook} =
        Webhooks.receive_webhook(
          attrs.provider_code,
          attrs.event_id,
          attrs.event_type,
          attrs.raw_body,
          signature_valid: true,
          attempt_count: 3
        )

      assert webhook.attempt_count == 3
    end

    test "enqueues a WebhookProcessorWorker job" do
      attrs = event_attrs()

      {:ok, webhook} =
        Webhooks.receive_webhook(
          attrs.provider_code,
          attrs.event_id,
          attrs.event_type,
          attrs.raw_body
        )

      assert_enqueued(
        worker: YagyeCore.Webhooks.Workers.WebhookProcessorWorker,
        args: %{"webhook_event_id" => webhook.id}
      )
    end

    test "returns {:error, :already_received} on duplicate (provider_code + event_id)" do
      attrs = event_attrs()

      {:ok, _} =
        Webhooks.receive_webhook(
          attrs.provider_code,
          attrs.event_id,
          attrs.event_type,
          attrs.raw_body
        )

      assert {:error, :already_received} =
               Webhooks.receive_webhook(
                 attrs.provider_code,
                 attrs.event_id,
                 attrs.event_type,
                 attrs.raw_body
               )
    end

    test "same event_id from different providers is NOT a duplicate" do
      shared_event_id = "evt_shared_#{System.unique_integer([:positive])}"

      assert {:ok, _} =
               Webhooks.receive_webhook(
                 "provider_a",
                 shared_event_id,
                 "charge.succeeded",
                 ~s({"charge_ref":"chg_001"})
               )

      assert {:ok, _} =
               Webhooks.receive_webhook(
                 "provider_b",
                 shared_event_id,
                 "charge.succeeded",
                 ~s({"charge_ref":"chg_002"})
               )
    end

    test "duplicate does NOT roll back the original row" do
      attrs = event_attrs()

      {:ok, original} =
        Webhooks.receive_webhook(
          attrs.provider_code,
          attrs.event_id,
          attrs.event_type,
          attrs.raw_body
        )

      {:error, :already_received} =
        Webhooks.receive_webhook(
          attrs.provider_code,
          attrs.event_id,
          attrs.event_type,
          attrs.raw_body
        )

      assert Repo.get(WebhookEvent, original.id) != nil
    end
  end

  describe "mark_processed/1" do
    test "transitions state to processed and stamps processed_at" do
      attrs = event_attrs()

      {:ok, webhook} =
        Webhooks.receive_webhook(
          attrs.provider_code,
          attrs.event_id,
          attrs.event_type,
          attrs.raw_body
        )

      {:ok, updated} = Webhooks.mark_processed(webhook)

      assert updated.state == "processed"
      assert updated.processed_at != nil
    end
  end

  describe "mark_failed/2" do
    test "transitions state to failed and records the error" do
      attrs = event_attrs()

      {:ok, webhook} =
        Webhooks.receive_webhook(
          attrs.provider_code,
          attrs.event_id,
          attrs.event_type,
          attrs.raw_body
        )

      {:ok, updated} = Webhooks.mark_failed(webhook, "unknown charge_ref")

      assert updated.state == "failed"
      assert updated.error == "unknown charge_ref"
    end
  end
end
