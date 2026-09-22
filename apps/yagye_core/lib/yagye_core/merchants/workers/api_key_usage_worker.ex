defmodule YagyeCore.Merchants.Workers.ApiKeyUsageWorker do
  @moduledoc false

  # Async, fire-and-forget worker that records when an API key was last used.
  # Unique per key per 60s so burst traffic doesn't create thousands of jobs.

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:api_key_id], period: 60]

  alias YagyeCore.Merchants.Schemas.ApiKey
  alias YagyeCore.Outbox
  alias YagyeCore.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"api_key_id" => api_key_id}}) do
    now = DateTime.utc_now()

    case Repo.get(ApiKey, api_key_id) do
      nil ->
        :ok

      api_key ->
        with {:ok, updated} <-
               api_key
               |> Ecto.Changeset.change(last_used_at: now)
               |> Repo.update() do
          emit_usage_event(updated, now)
        end

        :ok
    end
  end

  defp emit_usage_event(api_key, used_at) do
    Outbox.build_changeset(
      api_key,
      "api_key.used",
      %{
        key_id: api_key.public_id,
        mode: api_key.mode,
        kind: api_key.kind,
        last_used_at: DateTime.to_iso8601(used_at)
      },
      destination: "kafka:yagye.api_keys.v1"
    )
    |> Repo.insert()
  end
end
