defmodule YagyeCore.Risk.ScoringClientTest do
  # async: false because each test overrides Application config for :scoring_req_opts
  use ExUnit.Case, async: false

  alias YagyeCore.Risk.ScoringClient

  setup do
    # Override the default stateless stub so Req.Test.stub/2 is consulted instead.
    original = Application.get_env(:yagye_core, :scoring_req_opts)

    Application.put_env(:yagye_core, :scoring_req_opts,
      plug: {Req.Test, :scoring_http},
      retry: false
    )

    on_exit(fn -> Application.put_env(:yagye_core, :scoring_req_opts, original) end)
    :ok
  end

  defp payment do
    %{
      id: Ecto.UUID.generate(),
      amount: 50_000,
      currency: "GHS",
      method: "mobile_money",
      mode: "live",
      metadata: %{"msisdn_hash" => "abc123hash"},
      customer_id: Ecto.UUID.generate()
    }
  end

  defp merchant do
    %{id: Ecto.UUID.generate()}
  end

  # ── score_risk/2 ─────────────────────────────────────────────────────────────

  describe "score_risk/2" do
    test "returns {:ok, response} on 200" do
      Req.Test.stub(:scoring_http, fn conn ->
        Req.Test.json(conn, %{
          "decision" => "allow",
          "score" => 0.12,
          "reasons" => []
        })
      end)

      assert {:ok, response} = ScoringClient.score_risk(payment(), merchant())
      assert response[:decision] == "allow"
      assert response[:score] == 0.12
    end

    test "returns {:ok, block decision} when score is high" do
      Req.Test.stub(:scoring_http, fn conn ->
        Req.Test.json(conn, %{
          "decision" => "block",
          "score" => 0.97,
          "reasons" => ["high_velocity", "new_merchant"]
        })
      end)

      assert {:ok, response} = ScoringClient.score_risk(payment(), merchant())
      assert response[:decision] == "block"
      assert response[:score] == 0.97
    end

    test "returns {:error, :scoring_unavailable} on 500" do
      Req.Test.stub(:scoring_http, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      assert {:error, :scoring_unavailable} = ScoringClient.score_risk(payment(), merchant())
    end

    test "returns {:error, :scoring_unavailable} on network error" do
      Req.Test.stub(:scoring_http, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :scoring_unavailable} = ScoringClient.score_risk(payment(), merchant())
    end
  end

  # ── score_routing/2 ──────────────────────────────────────────────────────────

  describe "score_routing/2" do
    test "returns {:ok, response} with provider ranking on 200" do
      Req.Test.stub(:scoring_http, fn conn ->
        Req.Test.json(conn, %{
          "routing_mode" => "provider_selection",
          "ranking" => ["provider_a", "mtn_momo"],
          "hold_reason" => nil
        })
      end)

      assert {:ok, response} = ScoringClient.score_routing(payment(), [])
      assert response[:routing_mode] == "provider_selection"
      assert response[:ranking] == ["provider_a", "mtn_momo"]
    end

    test "returns hold_all routing mode during system degradation" do
      Req.Test.stub(:scoring_http, fn conn ->
        Req.Test.json(conn, %{
          "routing_mode" => "hold_all",
          "ranking" => [],
          "hold_reason" => "provider_health_degraded"
        })
      end)

      assert {:ok, response} = ScoringClient.score_routing(payment(), [])
      assert response[:routing_mode] == "hold_all"
    end

    test "returns {:error, :scoring_unavailable} on timeout" do
      Req.Test.stub(:scoring_http, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :scoring_unavailable} = ScoringClient.score_routing(payment(), [])
    end
  end

  # ── Contract with yagye_scoring Pydantic schemas ─────────────────────────────

  describe "request contract" do
    test "score_risk sends every required RiskScoringRequest field and maps risk_score → score" do
      Req.Test.stub(:scoring_http, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        body = Jason.decode!(raw)

        for key <- ~w(payment_id merchant_id customer_msisdn_hash amount_minor hour_of_day
                      day_of_week customer_kyc_tier) do
          assert Map.has_key?(body, key), "missing #{key}"
        end

        assert body["customer_msisdn_hash"] == "abc123hash"
        assert body["day_of_week"] in 0..6

        Req.Test.json(conn, %{
          "payment_id" => body["payment_id"],
          "risk_score" => 0.42,
          "decision" => "review",
          "model_version" => "v1",
          "feature_source" => "realtime"
        })
      end)

      assert {:ok, %{score: 0.42, risk_score: 0.42, decision: "review"}} =
               ScoringClient.score_risk(payment(), merchant())
    end

    test "score_risk works for the pre-insert payment shell (id: nil)" do
      Req.Test.stub(:scoring_http, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        assert "pre_" <> _ = Jason.decode!(raw)["payment_id"]
        Req.Test.json(conn, %{"decision" => "allow", "risk_score" => 0.01})
      end)

      assert {:ok, %{decision: "allow"}} =
               ScoringClient.score_risk(%{payment() | id: nil}, merchant())
    end

    test "score_routing sends provider_candidates and maps provider_scores → ranking" do
      Req.Test.stub(:scoring_http, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        body = Jason.decode!(raw)

        assert body["provider_candidates"] == [
                 %{"provider_code" => "mtn_momo", "provider_kind" => "native_rail"}
               ]

        assert body["payment_method"] == "mobile_money"

        Req.Test.json(conn, %{
          "payment_id" => body["payment_id"],
          "provider_scores" => [
            %{"provider_code" => "mtn_momo", "provider_kind" => "native_rail", "score" => 0.9}
          ],
          "routing_mode" => "go_hold",
          "model_version" => "v1",
          "feature_source" => "realtime"
        })
      end)

      assert {:ok, %{ranking: ["mtn_momo"], routing_mode: "go_hold"}} =
               ScoringClient.score_routing(payment(), [%{code: "mtn_momo", kind: "native_rail"}])
    end
  end
end
