defmodule YagyeCore.Payments.ModeFlowTest do
  @moduledoc """
  End-to-end tests for the three-tier mode flow:

    simulation  — new merchant with no live/sandbox grant
    sandbox     — merchant with sandbox mode granted
    live        — approved merchant (live mode granted on approval)

  Each scenario verifies three things:
    1. `create_payment/2` stamps the correct mode on the payment.
    2. `Providers.get_provider_for_payment/2` resolves the right provider.
    3. The resolved provider code is correct (simulator vs. mtn_momo_gh).
  """

  use YagyeCore.DataCase, async: true

  alias YagyeCore.{Fixtures, Merchants, Payments, Providers}
  alias YagyeCore.Providers.Schemas.{Provider, ProviderCredential}
  alias YagyeCore.Repo
  alias YagyeCore.Routing.Schemas.{RoutingRule, RoutingRuleAction}
  alias YagyeCore.Shared.Vault

  # ── Fixtures ────────────────────────────────────────────────────────────────

  # Returns a simulator provider + platform credential (simulation mode).
  # Skips DB insert if the provider already exists in this sandbox.
  defp setup_simulator do
    provider = Fixtures.simulator_provider_fixture()
    _creds = Fixtures.simulator_credential_fixture(provider)
    provider
  end

  # Returns a native-rail MTN provider + platform credential for the given mode.
  defp setup_mtn_provider(mode) do
    provider =
      case Repo.get_by(Provider, code: "mtn_momo_test_#{mode}") do
        %Provider{} = p ->
          p

        nil ->
          %Provider{}
          |> Provider.changeset(%{
            code: "mtn_momo_test_#{mode}",
            display_name: "MTN MoMo (test #{mode})",
            adapter_module: "YagyeCore.Payments.Adapters.MTNMomoAdapter",
            kind: "native_rail",
            active: true,
            capabilities: %{"mobile_money_gh" => true}
          })
          |> Repo.insert!()
      end

    payload = %{
      "subscription_key" => "test_sub_key",
      "api_user_id" => Uniq.UUID.uuid7(),
      "api_key" => "test_api_key",
      "target_environment" => mode
    }

    %ProviderCredential{}
    |> ProviderCredential.changeset(%{
      provider_id: provider.id,
      merchant_id: nil,
      mode: mode,
      base_url: "https://sandbox.momodeveloper.mtn.com",
      encrypted_payload: Vault.encrypt_map(payload),
      active: true
    })
    |> Repo.insert!()

    provider
  end

  # Seeds a platform routing rule (no conditions = catch-all) for the given
  # mode, pointing to the given provider. Uses priority 9999 (lowest — matches
  # production seed pattern).
  defp setup_routing_rule(mode, provider) do
    {:ok, rule} =
      %RoutingRule{}
      |> RoutingRule.changeset(%{
        scope: "platform",
        mode: mode,
        name: "test_mtn_#{mode}",
        priority: 9999,
        active: true
      })
      |> Repo.insert()

    {:ok, _action} =
      %RoutingRuleAction{}
      |> RoutingRuleAction.changeset(%{
        rule_id: rule.id,
        provider_id: provider.id,
        priority: 0
      })
      |> Repo.insert()

    rule
  end

  defp payment_attrs do
    %{amount: 10_000, currency: "GHS", rail: "fiat_provider", method: "mobile_money"}
  end

  # ── Simulation mode ──────────────────────────────────────────────────────────

  describe "simulation mode — new merchant with no mode grant" do
    setup do
      simulator = setup_simulator()
      merchant = Fixtures.merchant_fixture()
      %{merchant: merchant, simulator: simulator}
    end

    test "payment is stamped with mode: simulation", %{merchant: merchant} do
      assert {:ok, {payment, _event}} = Payments.create_payment(merchant.id, payment_attrs())
      assert payment.mode == "simulation"
    end

    test "get_provider_for_payment routes to the simulator", %{
      merchant: merchant,
      simulator: simulator
    } do
      {:ok, {payment, _}} = Payments.create_payment(merchant.id, payment_attrs())

      assert {:ok, {provider, _credential, %{source: :static}}} =
               Providers.get_provider_for_payment(payment, [])

      assert provider.id == simulator.id
      assert provider.code == "simulator"
    end

    test "sandbox_mode_enabled? returns false", %{merchant: merchant} do
      refute Merchants.sandbox_mode_enabled?(merchant.id)
    end

    test "live_mode_enabled? returns false", %{merchant: merchant} do
      refute Merchants.live_mode_enabled?(merchant.id)
    end
  end

  # ── Sandbox mode ─────────────────────────────────────────────────────────────

  describe "sandbox mode — merchant with sandbox grant" do
    setup do
      mtn_provider = setup_mtn_provider("sandbox")
      _rule = setup_routing_rule("sandbox", mtn_provider)
      merchant = Fixtures.merchant_fixture()
      {:ok, _} = Merchants.grant_sandbox_mode(merchant.id)
      %{merchant: merchant, mtn_provider: mtn_provider}
    end

    test "payment is stamped with mode: sandbox", %{merchant: merchant} do
      assert {:ok, {payment, _event}} = Payments.create_payment(merchant.id, payment_attrs())
      assert payment.mode == "sandbox"
    end

    test "get_provider_for_payment routes to mtn_momo via routing rule", %{
      merchant: merchant,
      mtn_provider: mtn_provider
    } do
      {:ok, {payment, _}} = Payments.create_payment(merchant.id, payment_attrs())

      assert {:ok, {provider, _credential, %{source: :rule}}} =
               Providers.get_provider_for_payment(payment, [])

      assert provider.id == mtn_provider.id
    end

    test "sandbox_mode_enabled? returns true", %{merchant: merchant} do
      assert Merchants.sandbox_mode_enabled?(merchant.id)
    end

    test "live_mode_enabled? returns false for sandbox-only merchant", %{merchant: merchant} do
      refute Merchants.live_mode_enabled?(merchant.id)
    end

    test "simulation merchant does not receive sandbox routing", %{mtn_provider: mtn_provider} do
      # A plain merchant (no modes granted) should NOT route to MTN even when
      # a sandbox routing rule exists — they stay in simulation.
      setup_simulator()
      plain_merchant = Fixtures.merchant_fixture()
      {:ok, {payment, _}} = Payments.create_payment(plain_merchant.id, payment_attrs())

      assert payment.mode == "simulation"

      assert {:ok, {provider, _credential, _meta}} =
               Providers.get_provider_for_payment(payment, [])

      assert provider.code == "simulator"
      assert provider.id != mtn_provider.id
    end
  end

  # ── Live mode ────────────────────────────────────────────────────────────────

  describe "live mode — approved merchant" do
    setup do
      mtn_provider = setup_mtn_provider("live")
      _rule = setup_routing_rule("live", mtn_provider)
      merchant = Fixtures.approved_merchant_fixture()
      %{merchant: merchant, mtn_provider: mtn_provider}
    end

    test "payment is stamped with mode: live", %{merchant: merchant} do
      assert {:ok, {payment, _event}} = Payments.create_payment(merchant.id, payment_attrs())
      assert payment.mode == "live"
    end

    test "get_provider_for_payment routes to mtn_momo via routing rule", %{
      merchant: merchant,
      mtn_provider: mtn_provider
    } do
      {:ok, {payment, _}} = Payments.create_payment(merchant.id, payment_attrs())

      assert {:ok, {provider, _credential, %{source: :rule}}} =
               Providers.get_provider_for_payment(payment, [])

      assert provider.id == mtn_provider.id
    end

    test "live_mode_enabled? returns true", %{merchant: merchant} do
      assert Merchants.live_mode_enabled?(merchant.id)
    end

    test "live takes priority over sandbox when both are granted", %{merchant: merchant} do
      # approved_merchant_fixture already has live; add sandbox too
      {:ok, _} = Merchants.grant_sandbox_mode(merchant.id)

      {:ok, {payment, _}} = Payments.create_payment(merchant.id, payment_attrs())

      # live wins
      assert payment.mode == "live"
    end
  end

  # ── Mode precedence ──────────────────────────────────────────────────────────

  describe "mode precedence" do
    test "live > sandbox > simulation" do
      merchant = Fixtures.merchant_fixture()

      # Start: simulation
      {:ok, {payment, _}} = Payments.create_payment(merchant.id, payment_attrs())
      assert payment.mode == "simulation"

      # Grant sandbox
      {:ok, _} = Merchants.grant_sandbox_mode(merchant.id)

      {:ok, {payment, _}} =
        Payments.create_payment(merchant.id, Map.put(payment_attrs(), :merchant_reference, "r1"))

      assert payment.mode == "sandbox"

      # Grant live — now live wins
      {:ok, {m, _}} = Merchants.submit_basic_info(merchant.public_id, "user:owner")
      {:ok, {m, _}} = Merchants.submit_documents(m.public_id, "user:owner")
      {:ok, {m, _}} = Merchants.start_review(m.public_id, "user:reviewer")
      {:ok, {_m, _}} = Merchants.approve(m.public_id, "user:approver")

      {:ok, {payment, _}} =
        Payments.create_payment(merchant.id, Map.put(payment_attrs(), :merchant_reference, "r2"))

      assert payment.mode == "live"
    end
  end
end
