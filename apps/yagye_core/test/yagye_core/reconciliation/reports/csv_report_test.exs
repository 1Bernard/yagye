defmodule YagyeCore.Reconciliation.Reports.CsvReportTest do
  use ExUnit.Case, async: true

  alias YagyeCore.Reconciliation.Reports.CsvReport

  @provider_id "prov-uuid-mno"
  @mode "live"

  defp valid_csv do
    """
    SETTLEMENT_DATE,LINE_NO,CHARGE_REF,LINE_TYPE,GROSS_PESEWAS,FEE_PESEWAS,NET_PESEWAS,VALUE_DATE
    2024-03-15,1,chg_abc123,collection,50000,1500,48500,2024-03-15
    2024-03-15,2,chg_def456,collection,100000,3000,97000,2024-03-15
    """
  end

  describe "parse/4 — source field (regression: was mno_csv)" do
    test "source is manual_upload not mno_csv" do
      {:ok, payload} = CsvReport.parse(@provider_id, @mode, valid_csv())
      assert payload.source == "manual_upload"
      refute payload.source == "mno_csv"
    end
  end

  describe "parse/4 — success" do
    test "returns ok with correct shape" do
      assert {:ok, payload} = CsvReport.parse(@provider_id, @mode, valid_csv())
      assert payload.line_count == 2
      assert payload.currency == "GHS"
    end

    test "maps CHARGE_REF to provider_reference" do
      {:ok, payload} = CsvReport.parse(@provider_id, @mode, valid_csv())
      refs = Enum.map(payload.lines, & &1.provider_reference)
      assert "chg_abc123" in refs
    end

    test "amounts parsed as integers (pesewas)" do
      {:ok, payload} = CsvReport.parse(@provider_id, @mode, valid_csv())
      line = hd(payload.lines)
      assert is_integer(line.gross_amount)
      assert is_integer(line.fee_amount)
      assert is_integer(line.net_amount)
    end
  end

  describe "parse/4 — errors" do
    test "returns empty_file for blank input" do
      assert {:error, :empty_file} = CsvReport.parse(@provider_id, @mode, "")
    end

    test "returns parse_error for invalid integer" do
      csv = """
      SETTLEMENT_DATE,LINE_NO,CHARGE_REF,LINE_TYPE,GROSS_PESEWAS,FEE_PESEWAS,NET_PESEWAS,VALUE_DATE
      2024-03-15,1,chg_bad,collection,not_a_number,1500,48500,2024-03-15
      """

      assert {:error, {:parse_error, _}} = CsvReport.parse(@provider_id, @mode, csv)
    end
  end
end
