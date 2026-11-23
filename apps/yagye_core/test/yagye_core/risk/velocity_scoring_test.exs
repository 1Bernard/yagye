defmodule YagyeCore.Risk.VelocityScoringTest do
  # async: false — tests override Application config (global state)
  use YagyeCore.DataCase, async: false

  alias YagyeCore.Risk.VelocityScoring

  setup do
    original_opts = Application.get_env(:yagye_core, :scoring_req_opts)

    Application.put_env(:yagye_core, :scoring_req_opts,
      plug: {Req.Test, :velocity_http},
      retry: false
    )

    on_exit(fn ->
      Application.put_env(:yagye_core, :scoring_req_opts, original_opts)
    end)

    :ok
  end

  defp stub_velocity(anomaly_score, is_anomaly) do
    Req.Test.stub(:velocity_http, fn conn ->
      Req.Test.json(conn, %{
        "payment_id" => "pay_test",
        "anomaly_score" => anomaly_score,
        "is_anomaly" => is_anomaly,
        "model_version" => "rule_based_fallback",
        "feature_source" => "static_fallback"
      })
    end)
  end

  defp fake_payment(attrs \\ %{}) do
    Map.merge(
      %{
        id: Uniq.UUID.uuid7(),
        merchant_id: Uniq.UUID.uuid7(),
        amount: 10_00,
        method: "mobile_money",
        metadata: %{"msisdn_hash" => "abc123"}
      },
      attrs
    )
  end

  describe "score/2" do
    test "returns ok with low anomaly score for normal traffic" do
      stub_velocity(0.10, false)
      payment = fake_payment()
      assert {:ok, result} = VelocityScoring.score(payment, "abc123hash")
      assert result.anomaly_score == 0.10
      assert result.is_anomaly == false
      assert result.model_version == "rule_based_fallback"
    end

    test "returns ok with is_anomaly true for burst traffic" do
      stub_velocity(0.90, true)
      payment = fake_payment()
      assert {:ok, result} = VelocityScoring.score(payment, "abc123hash")
      assert result.is_anomaly == true
      assert result.anomaly_score == 0.90
    end

    test "returns :scoring_unavailable when service is down" do
      Req.Test.stub(:velocity_http, fn conn ->
        Plug.Conn.send_resp(conn, 503, "unavailable")
      end)

      payment = fake_payment()
      assert {:error, :scoring_unavailable} = VelocityScoring.score(payment, "abc123hash")
    end

    test "returns :scoring_unavailable on network error" do
      Req.Test.stub(:velocity_http, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      payment = fake_payment()
      assert {:error, :scoring_unavailable} = VelocityScoring.score(payment, "abc123hash")
    end

    test "handles nil payment id by generating a pre_ id" do
      stub_velocity(0.10, false)
      payment = fake_payment(%{id: nil})
      assert {:ok, _result} = VelocityScoring.score(payment, "abc123hash")
    end
  end
end
