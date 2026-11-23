defmodule YagyeCore.Reconciliation.ReconScoringTest do
  # async: false — tests override Application config (global state)
  use YagyeCore.DataCase, async: false

  alias YagyeCore.Reconciliation.ReconScoring

  setup do
    original_opts = Application.get_env(:yagye_core, :scoring_req_opts)

    Application.put_env(:yagye_core, :scoring_req_opts,
      plug: {Req.Test, :recon_http},
      retry: false
    )

    on_exit(fn ->
      Application.put_env(:yagye_core, :scoring_req_opts, original_opts)
    end)

    :ok
  end

  defp stub_recon(classification, confidence) do
    Req.Test.stub(:recon_http, fn conn ->
      Req.Test.json(conn, %{
        "break_id" => "brk_test",
        "classification" => classification,
        "confidence" => confidence,
        "model_version" => "rule_based_fallback"
      })
    end)
  end

  defp fake_break(attrs \\ %{}) do
    Map.merge(
      %{
        public_id: "brk_test_001",
        difference: 0,
        expected_amount: 10_00,
        actual_amount: 10_00,
        right_ref: "psp_ref_123",
        evidence: %{},
        detected_at: DateTime.utc_now()
      },
      attrs
    )
  end

  describe "score/1" do
    test "returns timing_difference for zero-delta aged break" do
      stub_recon("timing_difference", 0.82)
      break = fake_break(%{difference: 0, right_ref: "ref123"})
      assert {:ok, result} = ReconScoring.score(break)
      assert result.classification == "timing_difference"
      assert result.confidence == 0.82
      assert result.model_version == "rule_based_fallback"
    end

    test "returns missing_on_right when provider ref absent" do
      stub_recon("missing_on_right", 0.75)
      break = fake_break(%{difference: 50_000, right_ref: nil})
      assert {:ok, result} = ReconScoring.score(break)
      assert result.classification == "missing_on_right"
    end

    test "returns :scoring_unavailable when service is down" do
      Req.Test.stub(:recon_http, fn conn ->
        Plug.Conn.send_resp(conn, 503, "service unavailable")
      end)

      assert {:error, :scoring_unavailable} = ReconScoring.score(fake_break())
    end

    test "returns :scoring_unavailable on network error" do
      Req.Test.stub(:recon_http, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :scoring_unavailable} = ReconScoring.score(fake_break())
    end
  end

  describe "auto_classify?/1" do
    test "returns true when confidence >= 0.80" do
      result = %{classification: "timing_difference", confidence: 0.85, model_version: "v1"}
      assert ReconScoring.auto_classify?(result)
    end

    test "returns false when confidence < 0.80" do
      result = %{classification: "timing_difference", confidence: 0.75, model_version: "v1"}
      refute ReconScoring.auto_classify?(result)
    end

    test "returns false exactly at boundary minus epsilon" do
      result = %{classification: "amount_mismatch", confidence: 0.799, model_version: "v1"}
      refute ReconScoring.auto_classify?(result)
    end

    test "returns true exactly at boundary" do
      result = %{classification: "fee_discrepancy", confidence: 0.80, model_version: "v1"}
      assert ReconScoring.auto_classify?(result)
    end
  end
end
