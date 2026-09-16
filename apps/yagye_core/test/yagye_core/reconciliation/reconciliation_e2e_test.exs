defmodule YagyeCore.Reconciliation.ReconciliationE2ETest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}
  alias YagyeCore.Providers.Schemas.{Provider, ProviderCredential}
  alias YagyeCore.Reconciliation

  alias YagyeCore.Reconciliation.Schemas.{
    ReconciliationBreak,
    ReconciliationMatch,
    ReconciliationRun
  }

  alias YagyeCore.Reconciliation.SimulatorReport
  alias YagyeCore.Reconciliation.Workers.ReconciliationRunWorker
  alias YagyeCore.Repo
  alias YagyeCore.Shared.Vault

  setup do
    merchant = Fixtures.merchant_fixture()

    provider =
      %Provider{}
      |> Provider.changeset(%{
        code: "sim_e2e_#{System.unique_integer([:positive])}",
        display_name: "E2E Test Provider",
        kind: "native_rail",
        adapter_module: "YagyeCore.Payments.Adapters.SimulatorAdapter",
        active: true
      })
      |> Repo.insert!()

    _credential =
      %ProviderCredential{}
      |> ProviderCredential.changeset(%{
        provider_id: provider.id,
        merchant_id: nil,
        mode: "simulation",
        base_url: "http://simulator-test.local",
        encrypted_payload: Vault.encrypt_map(%{"api_key" => "test_sim_key"}),
        active: true
      })
      |> Repo.insert!()

    %{merchant: merchant, provider: provider}
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp succeeded_attempt(merchant, provider, ref) do
    payment =
      Fixtures.payment_fixture(merchant, %{currency: "GHS", mode: "simulation", amount: 50_000})

    attempt =
      Repo.insert!(
        PaymentAttempt.changeset(%PaymentAttempt{}, %{
          payment_id: payment.id,
          provider_id: provider.id,
          attempt_number: 1,
          state: "succeeded",
          provider_reference: ref,
          idempotency_token: Uniq.UUID.uuid7()
        })
      )

    {:ok, _} = payment |> Payment.transition_changeset("succeeded") |> Repo.update()
    {payment, attempt}
  end

  defp simulator_response(currency, lines) do
    gross = lines |> Enum.map(& &1["gross_minor"]) |> Enum.sum()
    fee = lines |> Enum.map(& &1["fee_minor"]) |> Enum.sum()
    net = lines |> Enum.map(& &1["net_minor"]) |> Enum.sum()

    %{
      "file_ref" => "SF_#{System.unique_integer([:positive])}",
      "settlement_date" => Date.to_iso8601(Date.utc_today()),
      "currency" => currency,
      "gross_minor" => gross,
      "fee_minor" => fee,
      "net_minor" => net,
      "line_count" => length(lines),
      "lines" => lines
    }
  end

  defp charge_line(ref, gross, line_number \\ 1) do
    fee = div(gross * 200, 10_000) + 20

    %{
      "line_number" => line_number,
      "charge_ref" => ref,
      "line_type" => "CHARGE",
      "gross_minor" => gross,
      "fee_minor" => fee,
      "net_minor" => gross - fee,
      "value_date" => Date.to_iso8601(Date.utc_today())
    }
  end

  defp stub_simulator(response_body) do
    Req.Test.stub(:simulator_http, fn conn ->
      Req.Test.json(conn, response_body)
    end)
  end

  # ── SimulatorReport.generate/3 ────────────────────────────────────────────────

  describe "SimulatorReport.generate/3" do
    test "maps HTTP response to ingest_report payload shape", %{provider: provider} do
      ref = "gw_e2e_#{System.unique_integer([:positive])}"
      stub_simulator(simulator_response("GHS", [charge_line(ref, 50_000)]))

      date = Date.utc_today()
      assert {:ok, payload} = SimulatorReport.generate(provider.id, "simulation", date)

      assert payload.provider_id == provider.id
      assert payload.mode == "simulation"
      assert payload.report_date == date
      assert payload.line_count == 1
      assert is_binary(payload.checksum)

      [line] = payload.lines
      assert line.provider_reference == ref
      assert line.gross_amount == 50_000
      assert line.transaction_type == "CHARGE"
      assert line.currency == "GHS"
      assert %DateTime{} = line.occurred_at
    end

    test "empty report when simulator returns no lines", %{provider: provider} do
      stub_simulator(simulator_response("GHS", []))

      date = Date.utc_today()
      assert {:ok, payload} = SimulatorReport.generate(provider.id, "simulation", date)
      assert payload.line_count == 0
      assert payload.lines == []
    end
  end

  # ── Full reconciliation pipeline ──────────────────────────────────────────────

  describe "full reconciliation pipeline" do
    test "all charges matched when simulator returns complete report",
         %{merchant: merchant, provider: provider} do
      ref = "gw_full_#{System.unique_integer([:positive])}"
      succeeded_attempt(merchant, provider, ref)

      stub_simulator(simulator_response("GHS", [charge_line(ref, 50_000)]))

      date = Date.utc_today()
      scope_start = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      scope_end = DateTime.add(scope_start, 86_400, :second)

      {:ok, payload} = SimulatorReport.generate(provider.id, "simulation", date)
      {:ok, _} = Reconciliation.ingest_report(provider.id, payload)

      {:ok, run} =
        Reconciliation.start_run("settlement", "simulation", scope_start, scope_end,
          provider_id: provider.id,
          merchant_id: merchant.id
        )

      assert :ok = perform_job(ReconciliationRunWorker, %{"run_id" => run.id})

      completed = Repo.get!(ReconciliationRun, run.id)
      assert completed.state == "completed"
      assert completed.matched_count == 1
      assert completed.break_count == 0

      match = Repo.get_by(ReconciliationMatch, run_id: run.id)
      assert match != nil
      assert match.strategy == "exact_reference"
    end

    test "missing_on_right break when simulator omits a charge",
         %{merchant: merchant, provider: provider} do
      ref_present = "gw_present_#{System.unique_integer([:positive])}"
      ref_missing = "gw_missing_#{System.unique_integer([:positive])}"

      succeeded_attempt(merchant, provider, ref_present)
      succeeded_attempt(merchant, provider, ref_missing)

      # Simulator returns only ref_present — ref_missing is omitted (missing_line defect)
      stub_simulator(simulator_response("GHS", [charge_line(ref_present, 50_000)]))

      date = Date.utc_today()
      scope_start = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      scope_end = DateTime.add(scope_start, 86_400, :second)

      {:ok, payload} = SimulatorReport.generate(provider.id, "simulation", date)
      {:ok, _} = Reconciliation.ingest_report(provider.id, payload)

      {:ok, run} =
        Reconciliation.start_run("settlement", "simulation", scope_start, scope_end,
          provider_id: provider.id,
          merchant_id: merchant.id
        )

      assert :ok = perform_job(ReconciliationRunWorker, %{"run_id" => run.id})

      completed = Repo.get!(ReconciliationRun, run.id)
      assert completed.matched_count == 1
      assert completed.break_count == 1

      break =
        Repo.get_by(ReconciliationBreak,
          run_id: run.id,
          classification: "missing_on_right"
        )

      assert break != nil
      assert break.left_ref == ref_missing
    end

    test "orphan report line creates missing_on_left break",
         %{provider: provider} do
      orphan_ref = "gw_orphan_#{System.unique_integer([:positive])}"

      # Report has a line for a charge that has no corresponding payment attempt
      stub_simulator(simulator_response("GHS", [charge_line(orphan_ref, 50_000)]))

      date = Date.utc_today()
      scope_start = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      scope_end = DateTime.add(scope_start, 86_400, :second)

      {:ok, payload} = SimulatorReport.generate(provider.id, "simulation", date)
      {:ok, _} = Reconciliation.ingest_report(provider.id, payload)

      {:ok, run} =
        Reconciliation.start_run("settlement", "simulation", scope_start, scope_end,
          provider_id: provider.id
        )

      assert :ok = perform_job(ReconciliationRunWorker, %{"run_id" => run.id})

      completed = Repo.get!(ReconciliationRun, run.id)
      assert completed.matched_count == 0
      assert completed.break_count == 1

      break =
        Repo.get_by(ReconciliationBreak,
          run_id: run.id,
          classification: "missing_on_left"
        )

      assert break != nil
      assert break.right_ref == orphan_ref
    end
  end
end
