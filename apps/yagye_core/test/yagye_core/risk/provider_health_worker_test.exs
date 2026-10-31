defmodule YagyeCore.Risk.Workers.ProviderHealthWorkerTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Risk.Workers.ProviderHealthWorker

  # These tests verify the worker can be invoked without crashing.
  # Redis writes are not verified here (integration tests cover that).
  # The worker degrades gracefully when no payment_attempt data exists.

  describe "perform/1" do
    test "returns :ok with no providers" do
      # No providers in DB — should complete without error
      assert :ok = ProviderHealthWorker.perform(%Oban.Job{args: %{}})
    end
  end

  describe "update_one/2" do
    test "returns :ok with no payment_attempt data" do
      provider_id = Ecto.UUID.generate()
      # Falls through to static defaults when no rows exist
      assert :ok = ProviderHealthWorker.update_one(provider_id, "test_provider")
    end
  end
end
