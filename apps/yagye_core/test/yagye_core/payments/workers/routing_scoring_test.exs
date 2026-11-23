defmodule YagyeCore.Payments.Workers.RoutingScoringTest do
  # async: false — overrides Application config (global state)
  use YagyeCore.DataCase, async: false

  import Mox

  alias YagyeCore.{Fixtures, Repo}
  alias YagyeCore.MockProviderAdapter
  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Payments.Workers.PaymentDispatchWorker

  setup :verify_on_exit!

  # Payment is created in setup using the default ScoringStub (risk_ml_enabled
  # defaults to false in test). Each test then overrides scoring_req_opts to
  # simulate different scorer states for the routing call.
  setup do
    merchant = Fixtures.merchant_fixture()
    provider = Fixtures.simulator_provider_fixture()
    _credential = Fixtures.simulator_credential_fixture(provider)
    payment = Fixtures.payment_fixture(merchant)
    %{payment: payment}
  end

  # maybe_score_routing_async fires Task.start (fire-and-forget) inside
  # PaymentDispatchWorker after the provider is selected. The Task calls
  # ScoringClient.score_routing and logs the result — it never influences
  # routing or the worker's return value. These tests verify that the dispatch
  # worker completes correctly regardless of the routing scorer's availability.
  #
  # Note: the Task.start runs in a separate process. When the scorer stub is
  # registered only in the test process (Req.Test per-process semantics), the
  # Task cannot reach it and fails silently — this is the expected failure mode
  # for the shadow routing path and is exactly what these tests exercise.

  describe "maybe_score_routing_async — dispatch is unaffected by scorer state" do
    test "worker succeeds when routing scorer is unreachable", %{payment: payment} do
      with_scorer_stub(fn conn -> Req.Test.transport_error(conn, :econnrefused) end, fn ->
        expect(MockProviderAdapter, :charge, fn _payment, _attempt, _credential ->
          {:ok, %{provider_reference: "gw_routing_econnrefused", auth_code: "AUTH1"}}
        end)

        assert {:ok, _} = perform_job(PaymentDispatchWorker, %{payment_id: payment.id}, [])
        assert Repo.get!(Payment, payment.id).state == "succeeded"
      end)
    end

    test "worker succeeds when routing scorer returns 5xx", %{payment: payment} do
      with_scorer_stub(
        fn conn -> Plug.Conn.send_resp(conn, 500, "scorer unavailable") end,
        fn ->
          expect(MockProviderAdapter, :charge, fn _payment, _attempt, _credential ->
            {:ok, %{provider_reference: "gw_routing_500", auth_code: "AUTH2"}}
          end)

          assert {:ok, _} = perform_job(PaymentDispatchWorker, %{payment_id: payment.id}, [])
          assert Repo.get!(Payment, payment.id).state == "succeeded"
        end
      )
    end

    test "worker succeeds when routing scorer returns hold_all mode", %{payment: payment} do
      with_scorer_stub(
        fn conn ->
          Req.Test.json(conn, %{
            "routing_mode" => "hold_all",
            "ranking" => [],
            "hold_reason" => "provider_health_degraded"
          })
        end,
        fn ->
          expect(MockProviderAdapter, :charge, fn _payment, _attempt, _credential ->
            {:ok, %{provider_reference: "gw_routing_hold_all", auth_code: "AUTH3"}}
          end)

          assert {:ok, _} = perform_job(PaymentDispatchWorker, %{payment_id: payment.id}, [])
          assert Repo.get!(Payment, payment.id).state == "succeeded"
        end
      )
    end
  end

  # ── Helper ───────────────────────────────────────────────────────────────────

  defp with_scorer_stub(stub_fn, test_fn) do
    original = Application.get_env(:yagye_core, :scoring_req_opts)

    Application.put_env(:yagye_core, :scoring_req_opts,
      plug: {Req.Test, :scoring_http},
      retry: false
    )

    Req.Test.stub(:scoring_http, stub_fn)

    try do
      test_fn.()
    after
      Application.put_env(:yagye_core, :scoring_req_opts, original)
    end
  end
end
