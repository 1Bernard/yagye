defmodule YagyeCore.Webhooks do
  @moduledoc false

  alias Ecto.Multi
  alias YagyeCore.Repo
  alias YagyeCore.Webhooks.Schemas.WebhookEvent
  alias YagyeCore.Webhooks.Workers.WebhookProcessorWorker

  # ── Public API ───────────────────────────────────────────────────────────────

  @doc """
  Receives and persists an inbound webhook. Idempotent on (provider_code, event_id).

  On first receipt: inserts a pending WebhookEvent and enqueues a
  WebhookProcessorWorker in the same transaction so delivery is atomic.

  On duplicate receipt: returns {:error, :already_received}.
  """
  def receive_webhook(provider_code, event_id, event_type, raw_body, opts \\ []) do
    changeset =
      WebhookEvent.changeset(%WebhookEvent{}, %{
        provider_code: provider_code,
        event_id: event_id,
        event_type: event_type,
        raw_body: raw_body,
        signature_valid: Keyword.get(opts, :signature_valid, true),
        attempt_count: Keyword.get(opts, :attempt_count, 1)
      })

    Multi.new()
    |> Multi.insert(:webhook, changeset)
    |> Multi.run(:job, fn _repo, %{webhook: webhook} ->
      {:ok, WebhookProcessorWorker.new(%{webhook_event_id: webhook.id}) |> Oban.insert!()}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{webhook: webhook}} -> {:ok, webhook}
      {:error, :webhook, cs, _} -> {:error, unique_conflict_reason(cs)}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  def mark_processed(%WebhookEvent{} = webhook) do
    webhook
    |> WebhookEvent.changeset(%{state: "processed", processed_at: DateTime.utc_now()})
    |> Repo.update()
  end

  def mark_failed(%WebhookEvent{} = webhook, error) do
    webhook
    |> WebhookEvent.changeset(%{state: "failed", error: error})
    |> Repo.update()
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp unique_conflict_reason(%Ecto.Changeset{errors: errors} = cs) do
    if Enum.any?(errors, fn {_field, {_, opts}} -> opts[:constraint] == :unique end),
      do: :already_received,
      else: cs
  end
end
