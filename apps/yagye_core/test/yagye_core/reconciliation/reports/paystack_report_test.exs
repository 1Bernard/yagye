defmodule YagyeCore.Reconciliation.Reports.PaystackReportTest do
  use ExUnit.Case, async: true

  alias YagyeCore.Reconciliation.Reports.PaystackReport

  @provider_id "prov-uuid-paystack"
  @mode "live"

  defp valid_csv do
    """
    Transaction Date,Reference,Amount,Fee,Net Amount,Status,Settlement Date
    2024-03-15,ref_abc123,50000,1500,48500,success,2024-03-15
    2024-03-15,ref_def456,100000,3000,97000,success,2024-03-15
    """
  end

  describe "parse/4 — success" do
    test "returns ok with correct shape for valid CSV" do
      assert {:ok, payload} = PaystackReport.parse(@provider_id, @mode, valid_csv())

      assert payload.provider_id == @provider_id
      assert payload.mode == @mode
      assert payload.source == "manual_upload"
      assert payload.currency == "GHS"
      assert payload.line_count == 2
      assert is_binary(payload.checksum)
    end

    test "sets provider_reference to Reference column (matches idempotency_token)" do
      {:ok, payload} = PaystackReport.parse(@provider_id, @mode, valid_csv())
      refs = Enum.map(payload.lines, & &1.provider_reference)
      assert "ref_abc123" in refs
      assert "ref_def456" in refs
    end

    test "amounts in pesewas (no conversion)" do
      {:ok, payload} = PaystackReport.parse(@provider_id, @mode, valid_csv())
      line = Enum.find(payload.lines, &(&1.provider_reference == "ref_abc123"))
      assert line.gross_amount == 50_000
      assert line.fee_amount == 1_500
      assert line.net_amount == 48_500
    end

    test "reported_total sums net_amount of all lines" do
      {:ok, payload} = PaystackReport.parse(@provider_id, @mode, valid_csv())
      assert payload.reported_total == 48_500 + 97_000
    end

    test "value_date parses from Settlement Date" do
      {:ok, payload} = PaystackReport.parse(@provider_id, @mode, valid_csv())
      assert Enum.all?(payload.lines, &(&1.value_date == ~D[2024-03-15]))
    end

    test "accepts custom currency" do
      {:ok, payload} = PaystackReport.parse(@provider_id, @mode, valid_csv(), "USD")
      assert payload.currency == "USD"
    end
  end

  describe "parse/4 — skips non-success rows" do
    test "filters out failed/reversed rows" do
      csv = """
      Transaction Date,Reference,Amount,Fee,Net Amount,Status,Settlement Date
      2024-03-15,ref_success,50000,1500,48500,success,2024-03-15
      2024-03-15,ref_failed,20000,600,19400,failed,2024-03-15
      2024-03-15,ref_reversed,15000,450,14550,reversed,2024-03-15
      """

      {:ok, payload} = PaystackReport.parse(@provider_id, @mode, csv)
      assert payload.line_count == 1
      assert hd(payload.lines).provider_reference == "ref_success"
    end
  end

  describe "parse/4 — errors" do
    test "returns empty_file for blank CSV" do
      assert {:error, :empty_file} = PaystackReport.parse(@provider_id, @mode, "")
    end

    test "returns empty_file for header-only CSV" do
      assert {:error, :empty_file} =
               PaystackReport.parse(
                 @provider_id,
                 @mode,
                 "Transaction Date,Reference,Amount,Fee,Net Amount,Status,Settlement Date\n"
               )
    end

    test "returns parse_error for missing required columns" do
      csv = """
      Date,Amount,Fee
      2024-03-15,50000,1500
      """

      assert {:error, {:parse_error, {:missing_columns, missing}}} =
               PaystackReport.parse(@provider_id, @mode, csv)

      assert "reference" in missing
    end

    test "returns parse_error for invalid amount" do
      csv = """
      Transaction Date,Reference,Amount,Fee,Net Amount,Status,Settlement Date
      2024-03-15,ref_bad,not_a_number,1500,48500,success,2024-03-15
      """

      assert {:error, {:parse_error, _}} = PaystackReport.parse(@provider_id, @mode, csv)
    end
  end

  describe "parse/4 — net amount fallback" do
    test "calculates net from gross minus fee when Net Amount column is absent" do
      csv = """
      Transaction Date,Reference,Amount,Fee,Status,Settlement Date
      2024-03-15,ref_nocalc,50000,1500,success,2024-03-15
      """

      {:ok, payload} = PaystackReport.parse(@provider_id, @mode, csv)
      assert hd(payload.lines).net_amount == 50_000 - 1_500
    end
  end
end
