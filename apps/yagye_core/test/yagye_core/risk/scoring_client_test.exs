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
end
