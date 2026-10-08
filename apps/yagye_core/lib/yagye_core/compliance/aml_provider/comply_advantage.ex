defmodule YagyeCore.Compliance.AmlProvider.ComplyAdvantage do
  @moduledoc """
  ComplyAdvantage AML screening adapter.

  Configure:
    config :yagye_core, :aml_provider, YagyeCore.Compliance.AmlProvider.ComplyAdvantage
    config :yagye_core, :comply_advantage, api_key: System.get_env("COMPLY_ADVANTAGE_API_KEY")
  """
  @behaviour YagyeCore.Compliance.AmlProvider

  @base_url "https://api.complyadvantage.com"

  @impl true
  def enrol(subject) do
    body = %{
      search_term: Map.get(subject, :name),
      fuzziness: 0.6,
      search_type: "company",
      filters: %{types: ["sanction", "warning", "pep"]}
    }

    case request(:post, "/searches", body) do
      {:ok, %{"data" => %{"id" => id, "hits" => hits}}} ->
        status =
          if Enum.any?(hits, &(&1["match_status"] == "potential_match")),
            do: "potential_match",
            else: "clean"

        {:ok, %{provider_id: to_string(id), status: status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def refresh(provider_id) do
    case request(:get, "/searches/#{provider_id}") do
      {:ok, %{"data" => %{"hits" => hits}}} ->
        status =
          if Enum.any?(hits, &(&1["match_status"] == "potential_match")),
            do: "potential_match",
            else: "clean"

        {:ok, %{status: status, hits: hits}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def fetch_hit(provider_hit_id) do
    case request(:get, "/searches/#{provider_hit_id}") do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── Private ─────────────────────────────────────────────────────────────────

  defp request(method, path, body \\ nil) do
    api_key = Application.get_env(:yagye_core, :comply_advantage, [])[:api_key]

    req =
      Req.new(
        base_url: @base_url,
        auth: {:basic, "#{api_key}:"},
        json: body,
        headers: [{"Content-Type", "application/json"}]
      )

    result =
      case method do
        :get -> Req.get(req, url: path)
        :post -> Req.post(req, url: path)
      end

    case result do
      {:ok, %{status: status, body: resp_body}} when status in 200..299 -> {:ok, resp_body}
      {:ok, %{status: status, body: resp_body}} -> {:error, {status, resp_body}}
      {:error, reason} -> {:error, reason}
    end
  end
end
