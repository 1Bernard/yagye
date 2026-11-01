defmodule YagyeCore.Reconciliation.Reports.FlutterwaveReportTest do
  use ExUnit.Case, async: true

  alias YagyeCore.Reconciliation.Reports.FlutterwaveReport

  @provider_id "prov-uuid-flutterwave"
  @mode "live"

  defp valid_csv do
    """
    id,txRef,flwRef,amount,currency,appfee,merchantfee,settlementAmount,createdAt
    123456,FLW-TX-REF-001,FLW-REF-001,500.00,GHS,15.00,0.00,485.00,2024-03-15T10:30:00Z
    789012,FLW-TX-REF-002,FLW-REF-002,1000.00,GHS,30.00,5.00,965.00,2024-03-15T14:00:00Z
    """
  end

  describe "parse/4 — success" do
    test "returns ok with correct shape" do
      assert {:ok, payload} = FlutterwaveReport.parse(@provider_id, @mode, valid_csv())

      assert payload.provider_id == @provider_id
      assert payload.mode == @mode
      assert payload.source == "manual_upload"
      assert payload.currency == "GHS"
      assert payload.line_count == 2
    end

    test "provider_reference is txRef (matches idempotency_token)" do
      {:ok, payload} = FlutterwaveReport.parse(@provider_id, @mode, valid_csv())
      refs = Enum.map(payload.lines, & &1.provider_reference)
      assert "FLW-TX-REF-001" in refs
      assert "FLW-TX-REF-002" in refs
    end

    test "converts major unit amounts to pesewas (* 100)" do
      {:ok, payload} = FlutterwaveReport.parse(@provider_id, @mode, valid_csv())
      line = Enum.find(payload.lines, &(&1.provider_reference == "FLW-TX-REF-001"))

      # 500.00 GHS * 100 = 50_000 pesewas
      assert line.gross_amount == 50_000
      # appfee 15.00 + merchantfee 0.00 = 15.00 * 100 = 1_500
      assert line.fee_amount == 1_500
      # settlementAmount 485.00 * 100 = 48_500
      assert line.net_amount == 48_500
    end

    test "second line amounts correct" do
      {:ok, payload} = FlutterwaveReport.parse(@provider_id, @mode, valid_csv())
      line = Enum.find(payload.lines, &(&1.provider_reference == "FLW-TX-REF-002"))

      assert line.gross_amount == 100_000
      # appfee 30 + merchantfee 5 = 35 * 100 = 3_500
      assert line.fee_amount == 3_500
      assert line.net_amount == 96_500
    end

    test "reported_total sums net_amounts" do
      {:ok, payload} = FlutterwaveReport.parse(@provider_id, @mode, valid_csv())
      assert payload.reported_total == 48_500 + 96_500
    end

    test "parses createdAt to occurred_at datetime" do
      {:ok, payload} = FlutterwaveReport.parse(@provider_id, @mode, valid_csv())
      line = hd(payload.lines)
      assert %DateTime{year: 2024, month: 3, day: 15} = line.occurred_at
    end

    test "stores flw_id in raw" do
      {:ok, payload} = FlutterwaveReport.parse(@provider_id, @mode, valid_csv())
      line = Enum.find(payload.lines, &(&1.provider_reference == "FLW-TX-REF-001"))
      assert line.raw["flw_id"] == "123456"
    end
  end

  describe "parse/4 — errors" do
    test "returns empty_file for blank CSV" do
      assert {:error, :empty_file} = FlutterwaveReport.parse(@provider_id, @mode, "")
    end

    test "returns empty_file for header-only CSV" do
      assert {:error, :empty_file} =
               FlutterwaveReport.parse(
                 @provider_id,
                 @mode,
                 "id,txRef,flwRef,amount,currency,appfee,merchantfee,settlementAmount,createdAt\n"
               )
    end

    test "returns parse_error for missing required columns" do
      csv = """
      id,flwRef,amount
      123,FLW-REF,500.00
      """

      assert {:error, {:parse_error, {:missing_columns, missing}}} =
               FlutterwaveReport.parse(@provider_id, @mode, csv)

      assert "txref" in missing
    end

    test "returns parse_error for invalid amount" do
      csv = """
      id,txRef,flwRef,amount,currency,appfee,merchantfee,settlementAmount,createdAt
      123456,FLW-TX-REF-001,FLW-REF-001,not_a_float,GHS,15.00,0.00,485.00,2024-03-15T10:30:00Z
      """

      assert {:error, {:parse_error, _}} = FlutterwaveReport.parse(@provider_id, @mode, csv)
    end
  end

  describe "parse/4 — net amount fallback" do
    test "calculates net from gross minus fees when settlementAmount absent" do
      csv = """
      id,txRef,flwRef,amount,currency,appfee,merchantfee,createdAt
      123,TX-001,REF-001,500.00,GHS,15.00,5.00,2024-03-15T10:00:00Z
      """

      {:ok, payload} = FlutterwaveReport.parse(@provider_id, @mode, csv)
      line = hd(payload.lines)
      # (500.00 - 15.00 - 5.00) * 100 = 480.00 * 100 = 48_000
      assert line.net_amount == 48_000
    end
  end
end
