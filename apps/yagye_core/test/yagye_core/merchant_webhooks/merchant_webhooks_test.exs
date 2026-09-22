defmodule YagyeCore.MerchantWebhooksTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.MerchantWebhooks
  alias YagyeCore.MerchantWebhooks.Schemas.MerchantWebhookEndpoint
  alias YagyeCore.Repo

  setup do
    merchant = Fixtures.merchant_fixture()

    {:ok, endpoint, _secret} =
      MerchantWebhooks.register_endpoint(merchant, %{
        "url" => "https://example.com/hook",
        "mode" => "test",
        "subscribed_events" => ["payment.succeeded"]
      })

    {:ok, merchant: merchant, endpoint: endpoint}
  end

  describe "update_endpoint/2 — cooldown guard" do
    test "allows re-enable when endpoint was manually disabled (no disabled_at)", %{
      endpoint: endpoint
    } do
      # Manually disable without setting disabled_at (not auto-suspended)
      Repo.update_all(
        from(e in MerchantWebhookEndpoint, where: e.id == ^endpoint.id),
        set: [active: false]
      )

      endpoint = Repo.get!(MerchantWebhookEndpoint, endpoint.id)
      assert {:ok, updated} = MerchantWebhooks.update_endpoint(endpoint, %{"active" => true})
      assert updated.active == true
    end

    test "returns cooldown error when re-enabling within 1 hour of auto-suspension", %{
      endpoint: endpoint
    } do
      disabled_at = DateTime.utc_now() |> DateTime.add(-30 * 60, :second)

      Repo.update_all(
        from(e in MerchantWebhookEndpoint, where: e.id == ^endpoint.id),
        set: [active: false, disabled_at: disabled_at, consecutive_failures: 5]
      )

      endpoint = Repo.get!(MerchantWebhookEndpoint, endpoint.id)

      assert {:error, {:cooldown, cooldown_until}} =
               MerchantWebhooks.update_endpoint(endpoint, %{"active" => true})

      expected_cooldown =
        DateTime.add(disabled_at, 3600, :second)

      assert DateTime.compare(cooldown_until, expected_cooldown) == :eq
    end

    test "allows re-enable and resets failure counters after cooldown has elapsed", %{
      endpoint: endpoint
    } do
      disabled_at = DateTime.utc_now() |> DateTime.add(-90 * 60, :second)

      Repo.update_all(
        from(e in MerchantWebhookEndpoint, where: e.id == ^endpoint.id),
        set: [active: false, disabled_at: disabled_at, consecutive_failures: 5]
      )

      endpoint = Repo.get!(MerchantWebhookEndpoint, endpoint.id)

      assert {:ok, updated} =
               MerchantWebhooks.update_endpoint(endpoint, %{"active" => true})

      assert updated.active == true
      assert updated.consecutive_failures == 0
      assert is_nil(updated.disabled_at)
    end

    test "normal update (no active change) bypasses cooldown entirely", %{endpoint: endpoint} do
      disabled_at = DateTime.utc_now() |> DateTime.add(-5 * 60, :second)

      Repo.update_all(
        from(e in MerchantWebhookEndpoint, where: e.id == ^endpoint.id),
        set: [active: false, disabled_at: disabled_at, consecutive_failures: 3]
      )

      endpoint = Repo.get!(MerchantWebhookEndpoint, endpoint.id)

      assert {:ok, updated} =
               MerchantWebhooks.update_endpoint(endpoint, %{
                 "url" => "https://example.com/hook-v2"
               })

      assert updated.url == "https://example.com/hook-v2"
      assert updated.active == false
    end

    test "disabling an active endpoint also bypasses cooldown", %{endpoint: endpoint} do
      assert {:ok, updated} =
               MerchantWebhooks.update_endpoint(endpoint, %{"active" => false})

      assert updated.active == false
    end
  end
end
