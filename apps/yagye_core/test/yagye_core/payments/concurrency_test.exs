defmodule YagyeCore.Payments.ConcurrencyTest do
  # async: false is required — these tests spawn Tasks that need shared sandbox access.
  # DataCase sets shared: true when async is false, so child processes get the connection.
  use YagyeCore.DataCase, async: false

  import Mox

  alias YagyeCore.{Fixtures, Payments, Repo}
  alias YagyeCore.MockProviderAdapter
  alias YagyeCore.Payments.Schemas.Payment

  # Allow all spawned Task processes to use MockProviderAdapter without explicit allow/2.
  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    provider = Fixtures.simulator_provider_fixture()
    Fixtures.simulator_credential_fixture(provider)
    :ok
  end

  # ── Concurrent payment creation ──────────────────────────────────────────────

  describe "concurrent payment creation" do
    test "30 payments across different merchants all insert without conflict" do
      merchants = for _ <- 1..30, do: Fixtures.merchant_fixture()

      results =
        Task.async_stream(
          merchants,
          fn m ->
            Payments.create_payment(m.id, %{
              amount: 10_000,
              currency: "GHS",
              rail: "fiat_provider",
              method: "mobile_money"
            })
          end,
          max_concurrency: 30,
          timeout: 15_000
        )
        |> Enum.to_list()

      assert length(results) == 30

      assert Enum.all?(results, &match?({:ok, {:ok, _}}, &1)),
             "Some concurrent inserts failed: #{inspect(Enum.reject(results, &match?({:ok, {:ok, _}}, &1)))}"
    end
  end

  # ── Queue drain — all succeed ─────────────────────────────────────────────────

  describe "Oban queue drain — success path" do
    test "20 payments created concurrently all settle to succeeded" do
      stub(MockProviderAdapter, :charge, fn _payment, _attempt, _credential ->
        ref = "gw_ref_#{System.unique_integer([:positive])}"
        {:ok, %{provider_reference: ref, auth_code: "AUTH"}}
      end)

      payments =
        for _ <- 1..20 do
          merchant = Fixtures.merchant_fixture()

          {:ok, {payment, _}} =
            Payments.create_payment(merchant.id, %{
              amount: 5_000,
              currency: "GHS",
              rail: "fiat_provider",
              method: "mobile_money"
            })

          payment
        end

      Oban.drain_queue(queue: :payments)

      for payment <- payments do
        updated = Repo.get!(Payment, payment.id)

        assert updated.state == "succeeded",
               "Expected succeeded, got #{updated.state} for #{payment.public_id}"

        assert updated.version == 3

        {:ok, events} = Payments.list_events(payment.id)
        assert length(events) == 4

        event_types = Enum.map(events, & &1.event_type)

        assert event_types == [
                 "payment.created",
                 "payment.processing",
                 "payment.authorised",
                 "payment.succeeded"
               ]
      end
    end
  end

  # ── Queue drain — mixed outcomes ──────────────────────────────────────────────

  describe "Oban queue drain — mixed outcomes" do
    test "payments settle to correct terminal state based on provider response" do
      # Agent counter cycles 0,1,2 across concurrent charge calls — gives exact 7/7/7 split.
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      stub(MockProviderAdapter, :charge, fn _payment, _attempt, _cred ->
        n = Agent.get_and_update(counter, fn c -> {c, c + 1} end)

        case rem(n, 3) do
          0 ->
            {:ok, %{provider_reference: "gw_ok_#{n}", auth_code: "AUTH"}}

          1 ->
            {:error,
             %{
               error_class: :definite_failure,
               response_code: "DO_NOT_HONOR",
               response_message: nil
             }}

          2 ->
            {:error,
             %{error_class: :indeterminate, response_code: "timeout", response_message: nil}}
        end
      end)

      payments =
        for _ <- 1..21 do
          merchant = Fixtures.merchant_fixture()

          {:ok, {payment, _}} =
            Payments.create_payment(merchant.id, %{
              amount: 1_000,
              currency: "GHS",
              rail: "fiat_provider",
              method: "mobile_money"
            })

          payment
        end

      Oban.drain_queue(queue: :payments)

      terminal_states =
        payments
        |> Enum.map(fn p -> Repo.get!(Payment, p.id).state end)
        |> Enum.frequencies()

      # 7 of each outcome across 21 payments (attempt_number cycles 1,2,0)
      assert terminal_states["succeeded"] == 7
      assert terminal_states["failed"] == 7
      assert terminal_states["indeterminate"] == 7
    end
  end

  # ── Concurrent handle_provider_response — different payments ─────────────────

  describe "concurrent handle_provider_response" do
    test "parallel responses for 20 different payments do not corrupt state" do
      payments_and_attempts =
        for _ <- 1..20 do
          merchant = Fixtures.merchant_fixture()

          {:ok, {payment, _}} =
            Payments.create_payment(merchant.id, %{
              amount: 2_500,
              currency: "GHS",
              rail: "fiat_provider",
              method: "mobile_money"
            })

          {:ok, payment} = Payments.dispatch_payment(payment.id)

          {:ok, attempt} =
            Payments.create_attempt(payment, Fixtures.simulator_provider_fixture().id)

          {payment, attempt}
        end

      results =
        Task.async_stream(
          payments_and_attempts,
          fn {payment, attempt} ->
            result = {:ok, %{provider_reference: "gw_#{payment.id}", auth_code: "AUTH"}}
            Payments.handle_provider_response(payment, attempt, result)
          end,
          max_concurrency: 20,
          timeout: 10_000
        )
        |> Enum.to_list()

      assert Enum.all?(results, &match?({:ok, {:ok, _}}, &1)),
             "Some concurrent responses failed: #{inspect(Enum.reject(results, &match?({:ok, {:ok, _}}, &1)))}"

      for {payment, _} <- payments_and_attempts do
        updated = Repo.get!(Payment, payment.id)
        assert updated.state == "succeeded"
        assert updated.version == 3
      end
    end

    test "parallel definite failures for 20 different payments all land on failed" do
      payments_and_attempts =
        for _ <- 1..20 do
          merchant = Fixtures.merchant_fixture()

          {:ok, {payment, _}} =
            Payments.create_payment(merchant.id, %{
              amount: 2_500,
              currency: "GHS",
              rail: "fiat_provider",
              method: "mobile_money"
            })

          {:ok, payment} = Payments.dispatch_payment(payment.id)

          {:ok, attempt} =
            Payments.create_attempt(payment, Fixtures.simulator_provider_fixture().id)

          {payment, attempt}
        end

      fail_result =
        {:error,
         %{
           error_class: :definite_failure,
           response_code: "INSUFFICIENT_FUNDS",
           response_message: nil
         }}

      results =
        Task.async_stream(
          payments_and_attempts,
          fn {payment, attempt} ->
            Payments.handle_provider_response(payment, attempt, fail_result)
          end,
          max_concurrency: 20,
          timeout: 10_000
        )
        |> Enum.to_list()

      assert Enum.all?(results, &match?({:ok, {:ok, _}}, &1))

      for {payment, _} <- payments_and_attempts do
        updated = Repo.get!(Payment, payment.id)
        assert updated.state == "failed"
      end
    end
  end
end
