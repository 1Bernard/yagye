defmodule YagyeCore.ScoringStub do
  @moduledoc false
  # Stateless test plug for the scoring service. Always returns an "allow" risk
  # decision and an empty routing list. Used as the default scoring plug in
  # test.exs so that Task.start processes (spawned by score_risk_inline) don't
  # crash trying to look up a Req.Test stub that only lives in the test process
  # dictionary.
  #
  # ScoringClientTest overrides :scoring_req_opts per-test to use
  # {Req.Test, :scoring_http} so it can assert on specific responses.

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    body =
      if String.ends_with?(conn.request_path, "/routing") do
        %{
          "routing_mode" => "go_hold",
          "ranking" => [],
          "hold_reason" => nil,
          "model_version" => "test-stub",
          "feature_source" => "static_fallback"
        }
      else
        %{
          "decision" => "allow",
          "score" => 0.05,
          "reasons" => [],
          "model_version" => "test-stub",
          "feature_source" => "static_fallback"
        }
      end

    Req.Test.json(conn, body)
  end
end
