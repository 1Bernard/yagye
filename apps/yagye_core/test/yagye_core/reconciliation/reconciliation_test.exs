defmodule YagyeCore.Reconciliation.ReconciliationTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.Outbox.Schemas.OutboxMessage
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}
  alias YagyeCore.Providers.Schemas.Provider
  alias YagyeCore.Reconciliation

  alias YagyeCore.Reconciliation.Schemas.{
    ProviderReportLine,
    ProviderSettlementReport,
    ReconciliationBreak,
    ReconciliationMatch,
    ReconciliationRun
  }

  alias YagyeCore.Reconciliation.Workers.ReconciliationRunWorker
  alias YagyeCore.Repo

  # ── Fixtures ─────────────────────────────────────────────────────────────────

  defp provider_fixture do
    %Provider{}
    |> Provider.changeset(%{
      code: "rcn_prov_#{System.unique_integer([:positive])}",
      display_name: "Recon Test Provider",
      adapter_module: "YagyeCore.Payments.Adapters.SimulatorAdapter",
      active: true
    })
    |> Repo.insert!()
  end

  defp succeeded_attempt_fixture(merchant, provider, attrs) do
    currency = attrs[:currency] || "GHS"
    mode = attrs[:mode] || "simulation"
    amount = attrs[:amount] || 10_000
    ref = attrs[:provider_reference] || "chg_#{System.unique_integer([:positive])}"

    payment =
      Fixtures.payment_fixture(merchant, %{currency: currency, mode: mode, amount: amount})

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

    {:ok, payment} = payment |> Payment.transition_changeset("succeeded") |> Repo.update()
    {payment, attempt}
  end

  defp report_payload_fixture(provider, mode \\ "simulation", date \\ ~D[2026-08-23], lines \\ []) do
    default_lines = [
      %{
        line_number: 1,
        provider_reference: "chg_report_001",
        transaction_type: "CHARGE",
        gross_amount: 10_000,
        fee_amount: 220,
        net_amount: 9_780,
        currency: "GHS",
        occurred_at: DateTime.utc_now(),
        value_date: date,
        raw: %{"ref" => "chg_report_001", "type" => "CHARGE", "gross" => 10_000}
      }
    ]

    used_lines = if lines == [], do: default_lines, else: lines
    total = used_lines |> Enum.map(& &1.net_amount) |> Enum.sum()

    payload = %{
      provider_id: provider.id,
      mode: mode,
      report_date: date,
      source: "api",
      raw_uri: "s3://yagye-sim/reports/#{Uniq.UUID.uuid7()}.json",
      currency: "GHS",
      reported_total: total,
      line_count: length(used_lines),
      lines: used_lines
    }

    checksum =
      payload
      |> Jason.encode!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    Map.put(payload, :checksum, checksum)
  end

  # ── ingest_report/2 ───────────────────────────────────────────────────────────

  describe "ingest_report/2" do
    test "inserts report and lines, returns the report" do
      provider = provider_fixture()
      payload = report_payload_fixture(provider)

      assert {:ok, report} = Reconciliation.ingest_report(provider.id, payload)
      assert report.provider_id == provider.id
      assert report.line_count == 1
      assert Repo.get(ProviderSettlementReport, report.id) != nil

      line = Repo.get_by(ProviderReportLine, report_id: report.id, line_number: 1)
      assert line != nil
      assert line.match_state == "unmatched"
    end

    test "emits reconciliation.report.ingested outbox event" do
      provider = provider_fixture()
      payload = report_payload_fixture(provider)

      {:ok, report} = Reconciliation.ingest_report(provider.id, payload)

      msg =
        Repo.get_by(OutboxMessage,
          aggregate_type: "providersettlementreport",
          aggregate_id: report.id,
          event_type: "reconciliation.report.ingested"
        )

      assert msg != nil
    end

    test "idempotent: re-delivering the same checksum returns already_ingested" do
      provider = provider_fixture()
      payload = report_payload_fixture(provider)

      {:ok, first} = Reconciliation.ingest_report(provider.id, payload)

      assert {:error, {:already_ingested, existing}} =
               Reconciliation.ingest_report(provider.id, payload)

      assert existing.id == first.id
    end

    test "different checksum for same date creates a new row (amended report)" do
      provider = provider_fixture()
      payload1 = report_payload_fixture(provider)

      payload2 =
        report_payload_fixture(provider, "simulation", ~D[2026-08-23], [
          %{
            line_number: 1,
            provider_reference: "chg_amended_001",
            transaction_type: "CHARGE",
            gross_amount: 15_000,
            fee_amount: 320,
            net_amount: 14_680,
            currency: "GHS",
            occurred_at: DateTime.utc_now(),
            value_date: ~D[2026-08-23],
            raw: %{"ref" => "chg_amended_001", "type" => "CHARGE"}
          }
        ])

      {:ok, r1} = Reconciliation.ingest_report(provider.id, payload1)
      {:ok, r2} = Reconciliation.ingest_report(provider.id, payload2)
      assert r1.id != r2.id
      assert Repo.aggregate(ProviderSettlementReport, :count, :id) == 2
    end

    test "bad lines are quarantined, not fatal" do
      provider = provider_fixture()

      lines = [
        %{
          line_number: 1,
          provider_reference: "chg_ok",
          transaction_type: "CHARGE",
          gross_amount: 5_000,
          fee_amount: 120,
          net_amount: 4_880,
          currency: "GHS",
          occurred_at: DateTime.utc_now(),
          value_date: ~D[2026-08-23],
          raw: %{"ref" => "chg_ok"}
        },
        # bad line: missing transaction_type → quarantined
        %{
          line_number: 2,
          provider_reference: "chg_bad",
          transaction_type: nil,
          gross_amount: 3_000,
          net_amount: 0,
          raw: %{"ref" => "chg_bad"}
        }
      ]

      payload = report_payload_fixture(provider, "simulation", ~D[2026-08-23], lines)
      assert {:ok, _report} = Reconciliation.ingest_report(provider.id, payload)

      good = Repo.get_by(ProviderReportLine, line_number: 1, match_state: "unmatched")
      bad = Repo.get_by(ProviderReportLine, line_number: 2, match_state: "quarantined")

      assert good != nil
      assert bad != nil
    end
  end

  # ── ReconciliationRunWorker (matching strategies) ─────────────────────────────

  describe "ReconciliationRunWorker" do
    setup do
      merchant = Fixtures.merchant_fixture()
      provider = provider_fixture()
      %{merchant: merchant, provider: provider}
    end

    test "exact_reference match: creates a match record and stamps line as matched",
         %{merchant: merchant, provider: provider} do
      ref = "chg_exact_#{System.unique_integer([:positive])}"

      {_payment, _attempt} =
        succeeded_attempt_fixture(merchant, provider, provider_reference: ref)

      date = Date.utc_today()
      scope_start = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      scope_end = DateTime.add(scope_start, 86_400, :second)

      {:ok, report} =
        Reconciliation.ingest_report(provider.id, %{
          provider_id: provider.id,
          mode: "simulation",
          report_date: date,
          source: "api",
          raw_uri: "s3://sim/r.json",
          checksum: "cs_#{ref}",
          currency: "GHS",
          reported_total: 9_780,
          line_count: 1,
          lines: [
            %{
              line_number: 1,
              provider_reference: ref,
              transaction_type: "CHARGE",
              gross_amount: 10_000,
              fee_amount: 220,
              net_amount: 9_780,
              currency: "GHS",
              occurred_at: DateTime.utc_now(),
              value_date: date,
              raw: %{"ref" => ref}
            }
          ]
        })

      {:ok, run} =
        Reconciliation.start_run("transaction", "simulation", scope_start, scope_end,
          provider_id: provider.id,
          merchant_id: merchant.id
        )

      assert :ok = perform_job(ReconciliationRunWorker, %{"run_id" => run.id})

      completed_run = Repo.get!(ReconciliationRun, run.id)
      assert completed_run.state == "completed"
      assert completed_run.matched_count == 1
      assert completed_run.break_count == 0

      match = Repo.get_by(ReconciliationMatch, run_id: run.id, strategy: "exact_reference")
      assert match != nil
      assert match.auto_accepted == true

      line = Repo.get_by(ProviderReportLine, report_id: report.id)
      assert line.match_state == "matched"
    end

    test "unmatched payment_attempt creates missing_on_right break",
         %{merchant: merchant, provider: provider} do
      date = Date.utc_today()
      scope_start = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      scope_end = DateTime.add(scope_start, 86_400, :second)

      # Attempt in scope but no corresponding report line
      succeeded_attempt_fixture(merchant, provider,
        provider_reference: "chg_no_report_#{System.unique_integer([:positive])}"
      )

      {:ok, run} =
        Reconciliation.start_run("transaction", "simulation", scope_start, scope_end,
          provider_id: provider.id,
          merchant_id: merchant.id
        )

      assert :ok = perform_job(ReconciliationRunWorker, %{"run_id" => run.id})

      completed_run = Repo.get!(ReconciliationRun, run.id)
      assert completed_run.state == "completed"
      assert completed_run.break_count >= 1

      break =
        Repo.one(
          from b in ReconciliationBreak,
            where: b.run_id == ^run.id and b.classification == "missing_on_right"
        )

      assert break != nil
      assert break.severity == "high"
    end

    test "unmatched report line creates missing_on_left break",
         %{provider: provider} do
      date = Date.utc_today()
      scope_start = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      scope_end = DateTime.add(scope_start, 86_400, :second)
      orphan_ref = "chg_orphan_#{System.unique_integer([:positive])}"

      Reconciliation.ingest_report(provider.id, %{
        provider_id: provider.id,
        mode: "simulation",
        report_date: date,
        source: "api",
        raw_uri: "s3://sim/r.json",
        checksum: "cs_orphan_#{orphan_ref}",
        currency: "GHS",
        reported_total: 9_780,
        line_count: 1,
        lines: [
          %{
            line_number: 1,
            provider_reference: orphan_ref,
            transaction_type: "CHARGE",
            gross_amount: 10_000,
            fee_amount: 220,
            net_amount: 9_780,
            currency: "GHS",
            occurred_at: DateTime.utc_now(),
            value_date: date,
            raw: %{"ref" => orphan_ref}
          }
        ]
      })

      {:ok, run} =
        Reconciliation.start_run("transaction", "simulation", scope_start, scope_end,
          provider_id: provider.id
        )

      assert :ok = perform_job(ReconciliationRunWorker, %{"run_id" => run.id})

      break =
        Repo.one(
          from b in ReconciliationBreak,
            where: b.run_id == ^run.id and b.classification == "missing_on_left"
        )

      assert break != nil
    end

    test "run is idempotent: re-running a completed run is a no-op",
         %{provider: provider} do
      date = Date.utc_today()
      scope_start = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      scope_end = DateTime.add(scope_start, 86_400, :second)

      {:ok, run} =
        Reconciliation.start_run("transaction", "simulation", scope_start, scope_end,
          provider_id: provider.id
        )

      assert :ok = perform_job(ReconciliationRunWorker, %{"run_id" => run.id})
      assert :ok = perform_job(ReconciliationRunWorker, %{"run_id" => run.id})

      assert Repo.aggregate(
               from(r in ReconciliationRun, where: r.id == ^run.id),
               :count,
               :id
             ) == 1
    end
  end

  # ── SoD constraint ────────────────────────────────────────────────────────────

  describe "adjustment approvals (SoD)" do
    setup do
      merchant = Fixtures.merchant_fixture()
      provider = provider_fixture()

      date = Date.utc_today()
      scope_start = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      scope_end = DateTime.add(scope_start, 86_400, :second)

      {:ok, run} =
        Reconciliation.start_run("transaction", "simulation", scope_start, scope_end,
          provider_id: provider.id,
          merchant_id: merchant.id
        )

      break =
        Repo.insert!(
          ReconciliationBreak.changeset(%ReconciliationBreak{}, %{
            run_id: run.id,
            merchant_id: merchant.id,
            provider_id: provider.id,
            mode: "simulation",
            classification: "amount_mismatch",
            severity: "high",
            expected_amount: 10_000,
            actual_amount: 9_500,
            difference: 500,
            currency: "GHS"
          })
        )

      %{break: break, merchant: merchant}
    end

    test "proposer cannot approve their own adjustment", %{break: break} do
      {:ok, approval} =
        Reconciliation.propose_adjustment(break.public_id, "user:alice", %{
          "amount" => 500,
          "direction" => "credit_merchant",
          "resolution_code" => "provider_shortfall"
        })

      assert {:error, :sod_violation} =
               Reconciliation.approve_adjustment(approval.id, "user:alice")
    end

    test "a different user can approve the adjustment", %{break: break} do
      {:ok, approval} =
        Reconciliation.propose_adjustment(break.public_id, "user:alice", %{
          "amount" => 500,
          "direction" => "credit_merchant",
          "resolution_code" => "provider_shortfall"
        })

      assert {:ok, approved} = Reconciliation.approve_adjustment(approval.id, "user:bob")
      assert approved.approved_by == "user:bob"
      assert approved.approved_at != nil
    end

    test "approval resolves the break and posts a correcting ledger entry", %{break: break} do
      {:ok, approval} =
        Reconciliation.propose_adjustment(break.public_id, "user:alice", %{
          "amount" => 500,
          "direction" => "credit_merchant",
          "resolution_code" => "provider_shortfall"
        })

      assert {:ok, _approved} = Reconciliation.approve_adjustment(approval.id, "user:bob")

      resolved_break = Repo.get!(ReconciliationBreak, break.id)
      assert resolved_break.state == "resolved"
      assert resolved_break.resolving_entry_id != nil
    end

    test "cannot approve an already-decided approval", %{break: break} do
      {:ok, approval} =
        Reconciliation.propose_adjustment(break.public_id, "user:alice", %{
          "amount" => 500,
          "direction" => "credit_merchant"
        })

      {:ok, _} = Reconciliation.approve_adjustment(approval.id, "user:bob")

      assert {:error, :already_decided} =
               Reconciliation.approve_adjustment(approval.id, "user:carol")
    end
  end
end
